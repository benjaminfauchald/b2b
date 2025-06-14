require 'resolv'
require 'timeout'

class DomainTestingService < KafkaService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # 5 second timeout for DNS lookups
  
  def initialize(domain: nil, batch_size: 100, max_retries: 3)
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
    super(service_name: 'domain_testing_service', action: 'test_dns')
  end
  
  def call
    return test_single_domain if domain
    test_domains_in_batches
  end
  
  # Legacy class methods for backward compatibility
  def self.test_dns(domain)
    new(domain: domain).send(:perform_dns_test)[:records]
  end
  
  def self.queue_all_domains
    domains = Domain.needing_service('domain_testing_service')
    count = 0
    
    domains.find_each do |domain|
      DomainDnsTestingWorker.perform_async(domain.id)
      count += 1
    end
    
    count
  end
  
  def self.queue_100_domains
    domains = Domain.needing_service('domain_testing_service').limit(100)
    count = 0
    
    domains.each do |domain|
      DomainDnsTestingWorker.perform_async(domain.id)
      count += 1
    end
    
    count
  end
  
  private
  
  def test_single_domain
    start_time = Time.current
    result = perform_dns_test
    duration = Time.current - start_time

    {
      status: result[:status],
      records: result[:records],
      duration: duration
    }
  end

  def test_domains_in_batches
    Domain.untested.find_each(batch_size: batch_size) do |domain|
      produce_message_with_retry(
        topic: 'domain_testing',
        payload: { domain: domain.domain }.to_json,
        key: domain.id.to_s,
        max_retries: max_retries
      )
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
      status: records.values.any?(&:any?) ? 'success' : 'no_records',
      records: records
    }
  rescue Resolv::ResolvError => e
    {
      status: 'error',
      records: { error: e.message }
    }
  end

  def produce_message_with_retry(topic:, payload:, key:, max_retries:)
    retries = 0
    begin
      produce_message(
        topic: topic,
        payload: payload,
        key: key
      )
    rescue StandardError => e
      retries += 1
      if retries < (max_retries || @max_retries)
        sleep(2 ** retries) # Exponential backoff
        retry
      end
      raise
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
end 