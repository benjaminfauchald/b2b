class DomainARecordTestJob < ApplicationJob
  queue_as :default
  
  sidekiq_options retry: 0

  def perform(domain_id)
    domain = Domain.find(domain_id)
    result = DomainARecordTestingService.test_a_record(domain)
    
    # Update domain with A record test result
    domain.update!(www: result)
    
    # Build context hash safely
    context = { domain_name: domain.domain, www_status: result ? 'active' : 'inactive' }
    if result.is_a?(Hash)
      context[:test_duration_ms] = (result[:duration] * 1000).to_i if result[:duration]
      context[:a_records] = result[:a_records] if result[:a_records]
      context[:error] = result[:error] if result[:error]
    end

    # Create audit log
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: 'domain_a_record_testing',
      action: 'test_a_record',
      status: result ? :success : :failed,
      context: context
    )
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Domain not found: #{domain_id}"
  rescue StandardError => e
    Rails.logger.error "Error processing A record test for domain #{domain_id}: #{e.message}"
    raise
  end
end 