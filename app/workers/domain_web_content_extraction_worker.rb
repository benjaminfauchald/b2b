class DomainWebContentExtractionWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 3

  def perform(domain_id)
    domain = Domain.find(domain_id)
    service = DomainWebContentExtractionService.new(domain: domain)
    result = service.perform

    unless result.success?
      Rails.logger.error("Web content extraction failed for domain #{domain.domain}: #{result.error}")
    end

    result
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("Domain with ID #{domain_id} not found")
  rescue StandardError => e
    Rails.logger.error("Unexpected error in DomainWebContentExtractionWorker: #{e.message}")
    raise
  end
end