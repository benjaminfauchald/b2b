class DomainARecordTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: "DomainARecordTestingService", retry: 0

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain

    # Use audit system for tracking - the service handles all audit logging
    service = DomainARecordTestingService.new(domain: domain)
    service.call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Domain ##{domain_id} not found for A record testing"
  rescue StandardError => e
    Rails.logger.error "Error testing A record for domain ##{domain_id}: #{e.message}"
    raise
  end
end
