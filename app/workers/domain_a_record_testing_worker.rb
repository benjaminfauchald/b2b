class DomainARecordTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: :DomainARecordTestingService, retry: 3

  def perform(domain_id)
    domain = Domain.find(domain_id)
    
    domain.audit_service_operation('domain_a_record_testing_v1', action: 'test_a_record') do |audit_log|
      begin
        start_time = Time.current
        result = DomainARecordTestingService.new.send(:test_domain_a_record, domain, audit_log)
        duration = ((Time.current - start_time) * 1000).to_i

        # Update audit context with results
        audit_log.add_context(
          domain_name: domain.domain,
          www_result: result[:www_result],
          test_duration_ms: duration,
          www_status: result[:www_result] ? 'active' : 'inactive'
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