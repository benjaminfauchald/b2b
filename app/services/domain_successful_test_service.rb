class DomainSuccessfulTestService < ApplicationService
  def initialize(attributes = {})
    super(service_name: 'domain_successful_test', action: 'test_successful', **attributes)
  end

  private

  def perform
    # Only select domains where both DNS and WWW are true
    domains = Domain.where(dns: true, www: true)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }

    batch_process(domains) do |domain, audit_log|
      begin
        # Here you can add any logic you want to test on these successful domains
        # For demonstration, we'll just log the domain as successful
        audit_log.add_context(
          domain_name: domain.domain,
          dns: domain.dns,
          www: domain.www,
          status: 'success_both_dns_and_www'
        )
        results[:processed] += 1
        results[:successful] += 1
      rescue => e
        results[:errors] += 1
        audit_log.add_context(error: e.message)
        raise
      end
    end
    results
  end
end 