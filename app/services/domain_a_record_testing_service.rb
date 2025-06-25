require "resolv"
require "timeout"

class DomainARecordTestingService < ApplicationService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # seconds

  def initialize(domain: nil, batch_size: 100, max_retries: 3)
    super(service_name: "domain_a_record_testing", action: "test_a_record")
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
  end

  def call
    return test_single_domain if domain
    return { processed: 0, successful: 0, failed: 0, errors: 0 } unless service_active?
    test_domains_in_batches(Domain.dns_active.where(www: nil))
  end

  # Legacy class methods for backward compatibility
  def self.test_a_record(domain)
    new(domain: domain).send(:test_single_domain)
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
        domain.update(www: true)
        return true
      end
    rescue Resolv::ResolvError
      domain.update(www: false)
      false
    rescue Timeout::Error
      domain.update(www: false)
      false
    rescue StandardError
      domain.update(www: nil)
      nil
    end
  end

  private

  def test_single_domain
    audit_log = nil
    begin
      audit_log = ServiceAuditLog.create!(
        auditable: domain,
        service_name: service_name,
        operation_type: action,
        status: :pending,
        columns_affected: [ "www" ],
        metadata: { domain_name: domain.domain },
        table_name: domain.class.table_name,
        record_id: domain.id.to_s,
        started_at: Time.current
      )

      result = perform_a_record_test
      update_domain_status(domain, result)

      audit_log.update!(
        status: :success,
        completed_at: Time.current,
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
        metadata: audit_log.metadata.merge({
          www_status: domain.www,
          test_result: result[:status]
        })
      )

      result
    rescue StandardError => e
      if audit_log
        audit_log.update!(
          status: :failed,
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
          metadata: audit_log.metadata.merge({
            error: e.message,
            www_status: domain.www
          })
        )
      end
      raise e
    end
  end

  def perform_a_record_test
    begin
      Timeout.timeout(DNS_TIMEOUT) do
        a_record = Resolv.getaddress("www.#{domain.domain}")
        {
          status: :success,
          a_record: a_record
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: :no_records,
        error: "A record resolution failed"
      }
    rescue Timeout::Error => e
      {
        status: :timeout,
        error: "A record resolution timed out after #{DNS_TIMEOUT} seconds"
      }
    end
  end

  def update_domain_status(domain, result)
    case result[:status]
    when :success
      domain.update_columns(www: true)
    when :no_records, :timeout
      domain.update_columns(www: false)
    end
  end

  def test_domains_in_batches(domains)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }

    domains.find_each do |domain|
      result = self.class.test_a_record(domain)
      results[:processed] += 1
      case result
      when true
        results[:successful] += 1
      when false
        results[:failed] += 1
      else
        results[:errors] += 1
      end
      produce_message_with_retry(domain.domain, result)
    end

    results
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
    ServiceConfiguration.active?(service_name)
  end

  def needs_www_testing?(domain)
    domain.dns? && domain.www.nil?
  end
end
