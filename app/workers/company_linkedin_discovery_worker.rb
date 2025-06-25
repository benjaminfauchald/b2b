class CompanyLinkedinDiscoveryWorker
  include Sidekiq::Worker

  sidekiq_options queue: "company_linkedin_discovery", retry: 3

  def perform(company_id)
    company = Company.find_by(id: company_id)
    return unless company

    Rails.logger.info "Starting LinkedIn discovery for company #{company.id} - #{company.company_name}"

    service = CompanyLinkedinDiscoveryService.new(company_id: company.id)
    result = service.perform

    if result.success?
      Rails.logger.info "Successfully discovered LinkedIn profile for company #{company.id}"
    else
      Rails.logger.error "Failed LinkedIn discovery for company #{company.id}: #{result.error}"
      raise result.error if result.data[:retry_after] # Re-raise for retry on rate limit
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Company not found: #{company_id}"
  rescue StandardError => e
    Rails.logger.error "Error in LinkedIn discovery worker: #{e.message}"
    raise # Re-raise for Sidekiq retry
  end
end
