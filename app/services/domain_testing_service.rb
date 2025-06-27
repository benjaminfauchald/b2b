require "resolv"
require "timeout"
require "ostruct"

class DomainTestingService < ApplicationService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # seconds

  def initialize(domain: nil, batch_size: 100, max_retries: 3, **options)
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
    super(service_name: "domain_testing", action: "test_dns", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    
    if domain
      test_single_domain
    else
      test_domains_in_batches(Domain.needing_service(service_name))
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  # Legacy class methods for backward compatibility
  def self.test_dns(domain_or_name)
    domain_name = domain_or_name.is_a?(String) ? domain_or_name : domain_or_name.domain
    result = begin
      Resolv::DNS.open { |dns| dns.getaddress(domain_name) }
      true
    rescue Resolv::ResolvError, SocketError
      false
    end
    if domain_or_name.is_a?(Domain)
      domain_or_name.update_columns(dns: result)
    end
    result
  end

  def self.queue_all_domains
    domains = Domain.needing_service("domain_testing")
    count = 0

    domains.find_each do |domain|
      DomainTestJob.perform_later(domain.id)
      count += 1
    end

    count
  end

  def self.queue_100_domains
    domains = Domain.needing_service("domain_testing").limit(100)
    count = 0

    domains.each do |domain|
      DomainTestJob.perform_later(domain.id)
      count += 1
    end

    count
  end

  def has_dns?(domain_name)
    resolver = Resolv::DNS.new
    resolver.timeouts = DNS_TIMEOUT

    begin
      Timeout.timeout(DNS_TIMEOUT) do
        resolver.getresources(domain_name, Resolv::DNS::Resource::IN::A).any?
      end
    rescue Resolv::ResolvError, Timeout::Error
      false
    end
  end

  def test_domain_dns(domain, audit_log)
    start_time = Time.current
    begin
      result = self.class.test_dns(domain.domain)
      duration = ((Time.current - start_time) * 1000).round(2)
      context = {
        "dns_result" => result,
        "domain_name" => domain.domain,
        "dns_status" => domain.dns,
        "test_duration_ms" => duration
      }
      if result
        domain.update_columns(dns: true)
        audit_log.add_context(context)
        audit_log.mark_success!({
          "domain_name" => domain.domain,
          "dns_status" => domain.dns,
          "test_duration_ms" => duration
        }, [ "dns" ])
        { status: :success, context: context }
      else
        domain.update_columns(dns: false)
        audit_log.add_context(context)
        audit_log.mark_failed!("DNS test failed", { "error" => "DNS test failed", "domain_name" => domain.domain }, [])
        { status: :failed, context: context }
      end
    rescue Resolv::ResolvError => e
      duration = ((Time.current - start_time) * 1000).round(2)
      context = {
        "dns_result" => false,
        "domain_name" => domain.domain,
        "dns_status" => "inactive",
        "test_duration_ms" => duration,
        "error_type" => "resolve_error"
      }
      domain.update_columns(dns: false)
      audit_log.add_context(context)
      audit_log.mark_failed!(e.message, { "error" => e.message, "domain_name" => domain.domain }, [])
      { status: :failed, context: context }
    rescue Timeout::Error => e
      duration = ((Time.current - start_time) * 1000).round(2)
      context = {
        "dns_result" => false,
        "domain_name" => domain.domain,
        "dns_status" => "inactive",
        "test_duration_ms" => duration,
        "error_type" => "timeout_error"
      }
      domain.update_columns(dns: false)
      audit_log.add_context(context)
      audit_log.mark_failed!(e.message, { "error" => e.message, "domain_name" => domain.domain }, [])
      { status: :failed, context: context }
    rescue StandardError => e
      duration = ((Time.current - start_time) * 1000).round(2)
      context = {
        "dns_result" => false,
        "domain_name" => domain.domain,
        "dns_status" => "inactive",
        "test_duration_ms" => duration,
        "error_type" => "network_error"
      }
      domain.update_columns(dns: nil)
      audit_log.add_context(context)
      audit_log.mark_failed!(e.message, { "error" => e.message, "domain_name" => domain.domain }, [])
      { status: :failed, context: context }
    end
  end

  def test_domains_in_batches(domains)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    
    domains.find_each(batch_size: batch_size) do |domain|
      begin
        audit_service_operation(domain) do |audit_log|
          result = perform_dns_test_for_domain(domain)
          update_domain_status(domain, result)
          
          audit_log.add_metadata(
            domain_name: domain.domain,
            dns_status: domain.dns,
            test_result: result[:status]
          )
          
          if result[:status] == "success"
            results[:successful] += 1
            success_result("DNS test completed", result: result)
          else
            results[:failed] += 1
            error_result(result[:error] || "DNS test failed")
          end
        end
        results[:processed] += 1
      rescue StandardError => e
        results[:errors] += 1
        Rails.logger.error "Error testing DNS for domain #{domain.domain}: #{e.message}"
      end
    end
    
    success_result("Batch DNS testing completed", 
                  processed: results[:processed],
                  successful: results[:successful], 
                  failed: results[:failed],
                  errors: results[:errors])
  end

  private

  def test_single_domain
    audit_service_operation(domain) do |audit_log|
      result = perform_dns_test
      update_domain_status(domain, result)
      
      # If DNS test was successful, automatically queue MX and A Record tests
      if result[:status] == "success"
        queue_follow_up_tests
      end
      
      audit_log.add_metadata(
        domain_name: domain.domain,
        dns_status: domain.dns,
        test_result: result[:status]
      )
      
      success_result("DNS test completed", result: result)
    end
  end

  def perform_dns_test
    resolver = Resolv::DNS.new
    records = {
      a: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::A).map(&:address),
      mx: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::MX).map(&:exchange),
      txt: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::TXT).map(&:strings).flatten
    }

    {
      status: records.values.any?(&:any?) ? "success" : "no_records",
      records: records
    }
  rescue Resolv::ResolvError => e
    {
      status: "error",
      records: { error: e.message }
    }
  end

  def update_domain_status(domain, result)
    case result[:status]
    when "success"
      domain.update_columns(dns: true)
    when "no_records", "error"
      domain.update_columns(dns: false)
    end
  end

  def perform_dns_test_for_domain(test_domain)
    resolver = Resolv::DNS.new
    resolver.timeouts = DNS_TIMEOUT

    begin
      Timeout.timeout(DNS_TIMEOUT) do
        records = {
          a: resolver.getresources(test_domain.domain, Resolv::DNS::Resource::IN::A).map(&:address),
          mx: resolver.getresources(test_domain.domain, Resolv::DNS::Resource::IN::MX).map(&:exchange),
          txt: resolver.getresources(test_domain.domain, Resolv::DNS::Resource::IN::TXT).map(&:strings).flatten
        }

        {
          status: records.values.any?(&:any?) ? "success" : "no_records",
          records: records
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: "error",
        error: "DNS resolution failed: #{e.message}",
        records: {}
      }
    rescue Timeout::Error => e
      {
        status: "error",
        error: "DNS resolution timed out after #{DNS_TIMEOUT} seconds",
        records: {}
      }
    end
  end

  def log_error(domain, error)
    Rails.logger.error(
      message: "Domain testing error",
      domain_id: domain.id,
      domain_name: domain.domain,
      error: error.message,
      error_type: error.class.name,
      timestamp: Time.current
    )
  end

  def service_active?
    config = ServiceConfiguration.find_by(service_name: service_name)
    return false unless config
    config.active?
  end

  def success_result(message, data = {})
    OpenStruct.new(
      success?: true,
      message: message,
      data: data,
      error: nil
    )
  end

  def error_result(message, data = {})
    OpenStruct.new(
      success?: false,
      message: nil,
      error: message,
      data: data
    )
  end

  def process_domain(domain)
    audit_log = ServiceAuditLog.create!(
      auditable: domain,
      service_name: service_name,
      operation_type: action,
      status: :pending,
      columns_affected: [ "dns" ],
      metadata: { domain_name: domain.domain }
    )
    result = test_single_domain_for(domain)
    if result == true
      audit_log.mark_success!
    else
      audit_log.mark_failed!("DNS test failed")
    end
  end

  def queue_follow_up_tests
    Rails.logger.info("DNS test successful for domain #{domain.domain}, queueing MX and A Record tests")

    # Queue MX testing if not already tested
    if domain.mx.nil?
      DomainMxTestingWorker.perform_async(domain.id)
      Rails.logger.info("Queued MX testing for domain #{domain.domain}")
    end

    # Queue A Record testing if not already tested
    if domain.www.nil?
      DomainARecordTestingWorker.perform_async(domain.id)
      Rails.logger.info("Queued A Record testing for domain #{domain.domain}")
    end
  end
end
