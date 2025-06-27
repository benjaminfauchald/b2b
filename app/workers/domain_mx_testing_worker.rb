class DomainMxTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: "domain_mx_testing", retry: 3

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain

    # Use audit system for tracking - the service handles all audit logging
    service = DomainMxTestingService.new(domain: domain)
    service.call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Domain ##{domain_id} not found for MX testing"
  rescue StandardError => e
    Rails.logger.error "Error testing MX for domain ##{domain_id}: #{e.message}"
    raise
  end
end
