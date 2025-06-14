require 'resolv'
require 'timeout'

class DomainMxTestingService < ApplicationService
  MX_TIMEOUT = 5 # 5 second timeout for MX lookups

  def initialize
    @service_name = 'domain_mx_testing'
    @action = 'test_mx'
    @audit_log = AuditLog.new(@service_name, @action)
  end

  private

  def perform
    # Only select domains where both DNS and WWW are true
    domains = Domain.where(dns: true, www: true)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }

    batch_process(domains) do |domain, audit_log|
      begin
        mx_result = check_mx_record(domain.domain)
        
        # Update the domain's MX status
        domain.update!(mx: mx_result)
        
        audit_log.add_context(
          domain_name: domain.domain,
          dns: domain.dns,
          www: domain.www,
          mx_result: mx_result,
          status: mx_result ? 'has_mx_record' : 'no_mx_record'
        )
        
        results[:processed] += 1
        if mx_result
          results[:successful] += 1
        else
          results[:failed] += 1
        end
      rescue => e
        results[:errors] += 1
        audit_log.add_context(error: e.message)
        raise
      end
    end
    results
  end

  def check_mx_record(domain)
    Timeout.timeout(MX_TIMEOUT) do
      resolver = Resolv::DNS.new
      mx_records = resolver.getresources(domain, Resolv::DNS::Resource::IN::MX)
      mx_records.any?
    end
  rescue Timeout::Error, Resolv::ResolvError
    false
  end
end 