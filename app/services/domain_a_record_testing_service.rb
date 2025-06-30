require "resolv"
require "timeout"
require "ostruct"

class DomainARecordTestingService < ApplicationService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # seconds

  def initialize(domain: nil, batch_size: 100, max_retries: 3, **options)
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
    super(service_name: "domain_a_record_testing", action: "test_a_record", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?

    if domain
      test_single_domain
    else
      test_domains_in_batches(Domain.dns_active.where(www: nil))
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  # Legacy class methods for backward compatibility
  def self.test_a_record(domain)
    service = new(domain: domain)
    result = service.send(:perform_a_record_test_for_domain, domain)
    service.send(:update_domain_status, domain, result)
    result[:status] == "success"
  end

  def self.queue_all_domains
    domains = Domain.dns_active.where(www: nil)
    count = 0

    domains.find_each do |domain|
      DomainARecordTestingWorker.perform_async(domain.id)
      count += 1
    end

    count
  end

  def self.queue_100_domains
    domains = Domain.dns_active.where(www: nil).limit(100)
    count = 0

    domains.each do |domain|
      DomainARecordTestingWorker.perform_async(domain.id)
      count += 1
    end

    count
  end

  def process_domain(domain)
    audit_log = ServiceAuditLog.create!(
      auditable: domain,
      service_name: service_name,
      operation_type: "test_a_record",
      status: :pending,
      columns_affected: [ "www" ],
      metadata: { domain_name: domain.domain }
    )
    result = test_single_domain_for(domain)
    if result == true
      audit_log.mark_success!
    else
      audit_log.mark_failed!("A record test failed")
    end
  end

  def test_single_domain_for(domain)
    begin
      Timeout.timeout(DNS_TIMEOUT) do
        a_record = Resolv.getaddress("www.#{domain.domain}")
        domain.update(www: true, a_record_ip: a_record)
        return true
      end
    rescue Resolv::ResolvError
      domain.update(www: false, a_record_ip: nil)
      false
    rescue Timeout::Error
      domain.update(www: false, a_record_ip: nil)
      false
    rescue StandardError
      domain.update(www: nil, a_record_ip: nil)
      nil
    end
  end

  private

  def test_single_domain
    audit_service_operation(domain) do |audit_log|
      previous_ip = domain.a_record_ip
      result = perform_a_record_test
      update_domain_status(domain, result)

      metadata = {
        domain_name: domain.domain,
        www_status: domain.www,
        test_result: result[:status],
        a_record: result[:a_record]
      }
      metadata[:error] = result[:error] if result[:error]
      metadata[:previous_a_record] = previous_ip if previous_ip.present?

      audit_log.add_metadata(metadata)

      success_result("A record test completed", result: result)
    end
  end

  def perform_a_record_test
    perform_a_record_test_for_domain(domain)
  end

  def perform_a_record_test_for_domain(test_domain)
    begin
      Timeout.timeout(DNS_TIMEOUT) do
        a_record = Resolv.getaddress("www.#{test_domain.domain}")
        {
          status: "success",
          a_record: a_record
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: "no_records",
        error: "A record resolution failed"
      }
    rescue Timeout::Error => e
      {
        status: "timeout",
        error: "A record resolution timed out after #{DNS_TIMEOUT} seconds"
      }
    rescue StandardError => e
      {
        status: "error",
        error: "Unexpected error: #{e.message}"
      }
    end
  end

  def update_domain_status(domain, result)
    case result[:status]
    when "success"
      domain.update_columns(www: true, a_record_ip: result[:a_record])
    when "no_records", "timeout"
      domain.update_columns(www: false, a_record_ip: nil)
    when "error"
      domain.update_columns(www: nil, a_record_ip: nil)
    end
  end

  def test_domains_in_batches(domains)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }

    domains.find_each(batch_size: batch_size) do |domain|
      begin
        audit_service_operation(domain) do |audit_log|
          result = perform_a_record_test_for_domain(domain)
          update_domain_status(domain, result)

          audit_log.add_metadata(
            domain_name: domain.domain,
            www_status: domain.www,
            test_result: result[:status],
            a_record: result[:a_record]
          )

          case result[:status]
          when "success"
            results[:successful] += 1
            success_result("A record test completed", result: result)
          else
            results[:failed] += 1
            error_result(result[:error] || "A record test failed")
          end
        end
        results[:processed] += 1
        # TODO: Enable when Kafka is configured
        # produce_message_with_retry(domain.domain, result)
      rescue StandardError => e
        results[:errors] += 1
        Rails.logger.error "Error testing A record for domain #{domain.domain}: #{e.message}"
      end
    end

    success_result("Batch A record testing completed",
                  processed: results[:processed],
                  successful: results[:successful],
                  failed: results[:failed],
                  errors: results[:errors])
  end

  def produce_message_with_retry(domain_name, result)
    retries = 0
    begin
      produce_message(
        topic: "domain_a_record_testing",
        payload: {
          domain: domain_name,
          status: result,
          timestamp: Time.current.iso8601
        }.to_json,
        key: domain_name
      )
    rescue StandardError => e
      retries += 1
      if retries <= max_retries
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        log_error(domain_name, e)
      end
    end
  end

  def log_error(domain_name, error)
    Rails.logger.error(
      message: "Failed to produce message for domain",
      domain: domain_name,
      error: error.message,
      error_type: error.class.name
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

  def needs_www_testing?(domain)
    domain.dns? && domain.www.nil?
  end
end
