require 'resolv'
require 'timeout'

class DomainARecordTestingService < ApplicationService
  A_RECORD_TIMEOUT = 5 # 5 second timeout for A record lookups
  
  def initialize(attributes = {})
    super(service_name: 'domain_a_record_testing_v1', action: 'test_a_record', **attributes)
  end
  
  # Main service entry point
  def perform
    domains_needing_testing = Domain.dns_active.where(www: nil)
    
    if domains_needing_testing.empty?
      Rails.logger.info "No domains need A record testing at this time."
      return { processed: 0, results: {} }
    end
    
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    
    batch_process(domains_needing_testing) do |domain, audit_log|
      result = test_domain_a_record(domain, audit_log)
      
      results[:processed] += 1
      if result[:www_result]
        results[:successful] += 1
      else
        results[:failed] += 1
      end
      
      result
    rescue => e
      results[:errors] += 1
      Rails.logger.error "Error testing A record for #{domain.domain}: #{e.message}"
      raise
    end
    
    results
  end
  
  # Legacy class methods for backward compatibility
  def self.test_a_record(domain)
    new.send(:test_domain_a_record, domain)[:www_result]
  end
  
  # Queue methods for Sidekiq integration
  def self.queue_all_domains
    count = 0
    Domain.dns_active.where(www: nil).find_each do |domain|
      DomainARecordTestingWorker.perform_async(domain.id)
      count += 1
    end
    count
  end
  
  def self.queue_100_domains
    count = 0
    Domain.dns_active.where(www: nil).limit(100).each do |domain|
      DomainARecordTestingWorker.perform_async(domain.id)
      count += 1
    end
    count
  end
  
  private
  
  def test_domain_a_record(domain, audit_log)
    start_time = Time.current
    www_result = false

    begin
      Timeout.timeout(A_RECORD_TIMEOUT) do
        # Test www A record
        resolver = Resolv::DNS.new
        www_domain = "www.#{domain.domain}"
        addresses = resolver.getaddresses(www_domain)
        www_result = addresses.any?
      end
    rescue Timeout::Error
      Rails.logger.info "A record lookup timed out for www.#{domain.domain}"
      www_result = false
    rescue => e
      Rails.logger.error "Error testing A record for www.#{domain.domain}: #{e.message}"
      www_result = false
    end

    # Update domain
    domain.update!(www: www_result)

    # Return result
    {
      www_result: www_result,
      domain_name: domain.domain,
      test_duration_ms: ((Time.current - start_time) * 1000).to_i
    }
  end
end 