class DomainDnsTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: :DomainTestingService, retry: 3

  def perform(domain_id)
    domain = Domain.find(domain_id)
    
    domain.audit_service_operation('domain_testing_service', action: 'test_dns') do |audit_log|
      begin
        start_time = Time.current
        result = DomainTestingService.new.send(:test_domain_dns, domain, audit_log)
        duration = ((Time.current - start_time) * 1000).to_i

        # Update audit context with results
        audit_log.add_context(
          domain_name: domain.domain,
          dns_result: result[:dns_result],
          test_duration_ms: duration,
          dns_status: result[:dns_result] ? 'active' : 'inactive'
        )

        # Success is automatically handled by audit_service_operation
        result
      rescue => e
        # Error handling is automatically handled by audit_service_operation
        raise
      end
    end
  end
end 