class DomainTestJob < ApplicationJob
  queue_as :DomainTestingService

  # Set retry count to 0 as per requirements
  sidekiq_options retry: 0

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain  # Handle missing domain gracefully

    DomainTestingService.test_dns(domain)
  rescue => e
    # Swallow errors as per requirements (no logging for now)
    nil
  end
end
