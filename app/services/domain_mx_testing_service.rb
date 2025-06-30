require "resolv"
require "timeout"
require "ostruct"

class DomainMxTestingService < ApplicationService
  attr_reader :domain_obj, :batch_size, :max_retries

  MX_TIMEOUT = 5 # seconds

  def initialize(domain: nil, batch_size: 100, max_retries: 3, **options)
    @domain_obj = domain
    @batch_size = batch_size
    @max_retries = max_retries
    super(service_name: "domain_mx_testing", action: "test_mx", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?

    if domain_obj
      test_single_domain
    else
      test_domains_in_batches(Domain.needing_service("domain_mx_testing"))
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  def self.queue_all_domains
    domains = Domain.needing_service("domain_mx_testing")
    count = 0

    domains.find_each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      count += 1
    end

    count
  end

  def self.queue_100_domains
    domains = Domain.needing_service("domain_mx_testing").limit(100)
    count = 0

    domains.each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      count += 1
    end

    count
  end

  def check_mx_record(domain_name)
    resolver = Resolv::DNS.new
    begin
      Timeout.timeout(MX_TIMEOUT) do
        mx_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::MX)
        return !mx_records.empty?
      end
    rescue Timeout::Error, Resolv::ResolvError, StandardError
      false
    end
  end

  private

  def test_single_domain
    audit_service_operation(@domain_obj) do |audit_log|
      result = perform_mx_test(@domain_obj.domain)
      update_domain_status(@domain_obj, result)

      audit_log.add_metadata(
        domain_name: @domain_obj.domain,
        mx_status: @domain_obj.mx,
        test_duration_ms: result[:duration]
      )

      success_result("MX test completed", result: result)
    end
  end

  def test_domains_in_batches(domains)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }

    domains.find_each(batch_size: batch_size) do |domain|
      begin
        audit_service_operation(domain) do |audit_log|
          result = perform_mx_test(domain.domain)
          update_domain_status(domain, result)

          audit_log.add_metadata(
            domain_name: domain.domain,
            mx_status: domain.mx,
            test_duration_ms: result[:duration]
          )

          if result[:status] == "success"
            results[:successful] += 1
            success_result("MX test completed", result: result)
          else
            results[:failed] += 1
            error_result(result[:error] || "MX test failed")
          end
        end
        results[:processed] += 1
      rescue StandardError => e
        results[:errors] += 1
        Rails.logger.error "Error testing domain #{domain.domain}: #{e.message}"
      end
    end

    success_result("Batch MX testing completed",
                  processed: results[:processed],
                  successful: results[:successful],
                  failed: results[:failed],
                  errors: results[:errors])
  end

  def perform_mx_test(domain_name)
    start_time = Time.current
    resolver = Resolv::DNS.new
    begin
      Timeout.timeout(MX_TIMEOUT) do
        mx_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::MX)
        {
          status: mx_records.any? ? "success" : "no_records",
          mx_records: mx_records.map { |mx| mx.exchange.to_s },
          duration: Time.current - start_time
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: "error",
        error: "DNS resolution failed",
        duration: Time.current - start_time
      }
    rescue Timeout::Error => e
      {
        status: "error",
        error: "DNS resolution timed out after #{MX_TIMEOUT} seconds",
        duration: Time.current - start_time
      }
    end
  end

  def update_domain_status(domain, result)
    case result[:status]
    when "success"
      domain.update_columns(mx: true)
    when "no_records", "error", "timeout"
      domain.update_columns(mx: false)
    end
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

  # Legacy class methods for backward compatibility
  def self.test_mx(domain)
    service = new(domain: domain)
    result = service.send(:perform_mx_test, domain.domain)
    if result[:status] == "success"
      domain.update_columns(mx: true)
      true
    else
      domain.update_columns(mx: false)
      false
    end
  end
end
