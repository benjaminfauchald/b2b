require 'resolv'
require 'timeout'

class DomainARecordTestingService < ApplicationService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # seconds
  
  def initialize(domain: nil, batch_size: 100, max_retries: 3)
    super(action: 'test_a_record')
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
  end
  
  def call
    if domain
      if domain.needs_www_testing?(service_name)
        process_domain(domain)
      end
    else
      test_domains_in_batches
    end
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
    result = test_a_record(domain)
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: 'domain_a_record_testing',
      action: 'test_a_record',
      status: result ? :success : :failed,
      context: {
        domain_name: domain.domain,
        www_status: result ? 'active' : 'inactive'
      }
    )
  end

  def test_a_record(domain)
    # Simulate A record test logic here
    # For now, return true for simplicity
    true
  end
  
  private
  
  def test_single_domain
    begin
      Timeout.timeout(DNS_TIMEOUT) do
        a_record = Resolv.getaddress("www.#{domain.domain}")
        domain.update(www: true)
        return true
      end
    rescue Resolv::ResolvError
      domain.update(www: false)
      return false
    rescue Timeout::Error
      domain.update(www: false)
      return false
    rescue StandardError
      domain.update(www: nil)
      return nil
    end
  end

  def test_domains_in_batches
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    
    Domain.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |domain|
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
    end
    
    results
  end

  def produce_message_with_retry(domain_name, result)
    retries = 0
    begin
      produce_message(
        topic: 'domain_a_record_testing',
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
end 