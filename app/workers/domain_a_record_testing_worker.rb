class DomainARecordTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'DomainARecordTestingService', retry: 0

  def perform(domain_id)
    domain = Domain.find(domain_id)
    service = DomainARecordTestingService.new(domain: domain)
    result = service.call
    
    # Update domain with A record test result
    domain.update!(www: result[:status] == 'success')
    
    # Create audit log
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: 'domain_a_record_testing_service',
      action: 'test_a_record',
      status: result[:status] == 'success' ? :success : :failed,
      context: {
        domain_name: domain.domain,
        test_duration_ms: (result[:duration] * 1000).to_i,
        a_records: result[:records][:a],
        error: result[:records][:error]
      }
    )
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Domain not found: #{domain_id}"
  rescue StandardError => e
    Rails.logger.error "Error processing A record test for domain #{domain_id}: #{e.message}"
    raise
  end
end 