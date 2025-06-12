require 'resolv'
require 'timeout'

class DomainTestingService < ApplicationService
  DNS_TIMEOUT = 5 # 5 second timeout for DNS lookups
  
  def initialize(attributes = {})
    super(service_name: 'domain_testing_service', action: 'test_dns', **attributes)
  end
  
  # Main service entry point
  def perform
    domains_needing_testing = Domain.needing_service(service_name)
    
    if domains_needing_testing.empty?
      Rails.logger.info "No domains need DNS testing at this time."
      return { processed: 0, results: {} }
    end
    
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    
    batch_process(domains_needing_testing) do |domain, audit_log|
      result = test_domain_dns(domain, audit_log)
      results[:processed] += 1
      results[result[:status]] += 1
    end
    
    results
  end
  
  # Legacy class methods for backward compatibility
  def self.test_dns(domain)
    new.send(:test_domain_dns, domain)[:dns_result]
  end
  
  def self.queue_all_domains
    # Use the service to process all domains needing testing
    service = new
    domains = Domain.needing_service('domain_dns_testing_v1')
    
    domains.find_each do |domain|
      DomainTestJob.perform_later(domain.id)
    end
    
    domains.count
  end
  
  def self.queue_100_domains
    # Use the service to process 100 domains needing testing
    service = new
    domains = Domain.needing_service('domain_dns_testing_v1').limit(100)
    
    domains.find_each do |domain|
      DomainTestJob.perform_later(domain.id)
    end
    
    domains.count
  end
  
  private
  
  def test_domain_dns(domain, audit_log = nil)
    start_time = Time.current
    
    begin
      # Perform DNS test
      dns_result = has_dns?(domain.domain)
      
      # Update domain
      domain.update!(dns: dns_result)
      
      # Build context for audit log
      context_data = {
        'dns_result' => dns_result,
        'domain_name' => domain.domain,
        'test_duration_ms' => ((Time.current - start_time) * 1000).round,
        'dns_status' => dns_result ? 'active' : 'inactive'
      }
      
      # Mark audit log as successful if provided
      audit_log&.add_context(context_data)
      audit_log&.mark_success!(context_data)
      
      { status: :successful, dns_result: dns_result, context: context_data }
      
    rescue Resolv::ResolvError => e
      handle_dns_error(domain, audit_log, 'resolve_error', e.message, start_time)
    rescue Timeout::Error => e
      handle_dns_error(domain, audit_log, 'timeout_error', 'DNS lookup timed out', start_time)
    rescue StandardError => e
      handle_dns_error(domain, audit_log, 'network_error', e.message, start_time)
    end
  end
  
  def handle_dns_error(domain, audit_log, error_type, error_message, start_time)
    # Update domain based on error type
    case error_type
    when 'resolve_error', 'timeout_error'
      domain.update!(dns: false) # Treat as DNS failure
    when 'network_error'
      domain.update!(dns: nil) # Keep as untested due to network issues
    end
    
    # Build error context
    context_data = {
      'error_type' => error_type,
      'error_message' => error_message,
      'domain_name' => domain.domain,
      'test_duration_ms' => ((Time.current - start_time) * 1000).round,
      'dns_status' => domain.dns.nil? ? 'untested' : 'inactive'
    }
    
    # Mark audit log as failed if provided
    if audit_log
      audit_log.add_context(context_data)
      audit_log.mark_failed!(error_message, context_data)
    end
    
    status = error_type == 'network_error' ? :errors : :failed
    { status: status, dns_result: domain.dns, context: context_data }
  end
  
  def has_dns?(domain_name)
    Timeout::timeout(DNS_TIMEOUT) do
      Resolv.getaddress(domain_name)
    end
    true
  rescue Resolv::ResolvError, Timeout::Error
    false
  end
end 