require 'resolv'
require 'timeout'

class DomainTestingService < ApplicationService
  DNS_TIMEOUT = 5 # 5 second timeout for DNS lookups
  
  def initialize(attributes = {})
    super(service_name: 'domain_testing_service', action: 'test_dns', **attributes)
  end
  
  # Main service entry point
  def perform
    domains_needing_testing = Domain.untested
    
    if domains_needing_testing.empty?
      Rails.logger.info "No domains need DNS testing at this time."
      return { processed: 0, results: {} }
    end
    
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    
    batch_process(domains_needing_testing) do |domain, audit_log|
      result = test_domain_dns(domain, audit_log)
      
      results[:processed] += 1
      if result[:dns_result]
        results[:successful] += 1
      else
        results[:failed] += 1
      end
    rescue => e
      results[:errors] += 1
      Rails.logger.error "Error testing domain #{domain.domain}: #{e.message}"
      raise
    end
    
    results
  end
  
  # Legacy class methods for backward compatibility
  def self.test_dns(domain)
    new.send(:test_domain_dns, domain)[:dns_result]
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
  
  def test_domain_dns(domain, audit_log)
    dns_result = false
    
    begin
      Timeout.timeout(DNS_TIMEOUT) do
        # Try to resolve the domain
        resolver = Resolv::DNS.new
        addresses = resolver.getaddresses(domain.domain)
        dns_result = addresses.any?
      end
    rescue Timeout::Error
      Rails.logger.info "DNS lookup timed out for #{domain.domain}"
      dns_result = false
    rescue Resolv::ResolvError => e
      Rails.logger.info "DNS resolution failed for #{domain.domain}: #{e.message}"
      dns_result = false
    rescue => e
      Rails.logger.error "Unexpected error testing DNS for #{domain.domain}: #{e.message}"
      raise
    end
    
    # Update domain status
    domain.update!(dns: dns_result)
    
    { dns_result: dns_result }
  end
end 