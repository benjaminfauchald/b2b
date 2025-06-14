require 'resolv'
require 'timeout'

class DomainARecordTestingService < KafkaService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # seconds
  
  def initialize(domain = nil, batch_size: 100, max_retries: 3)
    super(service_name: 'domain_a_record_testing_service')
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
  end
  
  def call
    if domain
      test_single_domain
    else
      test_domains_in_batches
    end
  end
  
  # Legacy class methods for backward compatibility
  def self.test_a_record(domain)
    new(domain).call
  end
  
  def self.queue_all_domains
    Domain.find_each do |domain|
      DomainARecordTestingWorker.perform_async(domain.id)
    end
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
  
  private
  
  def test_single_domain
    result = perform_a_record_test(domain.domain)
    update_domain_status(result)
    result
  end

  def test_domains_in_batches
    Domain.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |domain|
        result = perform_a_record_test(domain.domain)
        update_domain_status(result)
        produce_message_with_retry(domain.domain, result)
      end
    end
  end

  def perform_a_record_test(domain_name)
    start_time = Time.current
    resolver = Resolv::DNS.new
    resolver.timeouts = DNS_TIMEOUT

    begin
      a_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::A)
      {
        status: :success,
        a_records: a_records.map(&:address).map(&:to_s),
        duration: Time.current - start_time
      }
    rescue Resolv::ResolvError => e
      {
        status: :error,
        error: e.message,
        duration: Time.current - start_time
      }
    rescue Timeout::Error => e
      {
        status: :timeout,
        error: "DNS lookup timed out after #{DNS_TIMEOUT} seconds",
        duration: Time.current - start_time
      }
    end
  end

  def update_domain_status(result)
    return unless domain

    case result[:status]
    when :success
      domain.update(www: result[:a_records].any?)
    when :error, :timeout
      domain.update(www: false)
    end
  end

  def produce_message_with_retry(domain_name, result)
    retries = 0
    begin
      produce_message(
        topic: 'domain_a_record_testing',
        payload: {
          domain: domain_name,
          status: result[:status],
          a_records: result[:a_records],
          error: result[:error],
          duration: result[:duration],
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
end 