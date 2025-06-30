class DomainDnsTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: "domain_dns_testing", retry: 3

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    unless domain
      Rails.logger.error "Domain ##{domain_id} not found for DNS testing"
      raise ActiveRecord::RecordNotFound, "Domain ##{domain_id} not found"
    end

    # Check if service is active before processing
    service_config = ServiceConfiguration.find_by(service_name: "domain_testing")
    unless service_config&.active?
      Rails.logger.warn "Service is disabled"
      return
    end

    # Use audit system for tracking - the service handles all audit logging
    service = DomainTestingService.new(domain: domain)
    service.call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Domain ##{domain_id} not found for DNS testing"
    raise
  rescue StandardError => e
    Rails.logger.error "Error testing DNS for domain ##{domain_id}: #{e.message}"
    raise
  end
end
