class DomainDnsTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'domain_dns_testing', retry: 3

  def perform(domain_id)
    domain = Domain.find(domain_id)
    
    domain.audit_service_operation('domain_testing', operation_type: 'test_dns') do |audit_log|
      begin
        start_time = Time.current
        service = DomainTestingService.new(domain: domain)
        result = service.send(:perform_dns_test)
        duration = ((Time.current - start_time) * 1000).to_i

        # Convert DNS records to strings for JSON storage
        records = result[:records].transform_values do |values|
          values.map(&:to_s)
        end

        # Update audit context with results
        audit_log.add_context(
          domain_name: domain.domain,
          dns_result: result[:status] == 'success',
          test_duration_ms: duration,
          dns_status: result[:status] == 'success' ? 'active' : 'inactive',
          records: records
        )

        # Update domain status
        domain.update!(dns: result[:status] == 'success')

        # Success is automatically handled by audit_service_operation
        result
      rescue => e
        # Error handling is automatically handled by audit_service_operation
        raise
      end
    end
  end
end 