class PersonProfileExtractionWorker
  include Sidekiq::Worker

  sidekiq_options queue: :person_profile_extraction, retry: 2

  def perform(company_id)
    Rails.logger.info "🚀 PersonProfileExtractionWorker: Starting profile extraction for company #{company_id}"

    # Use the async service
    service = PersonProfileExtractionAsyncService.new(company_id: company_id)
    result = service.perform

    if result.success?
      Rails.logger.info "✅ PersonProfileExtractionWorker: Profile extraction launched for company #{company_id}: #{result.message}"
      # The service now handles async monitoring, so we just return success
    else
      Rails.logger.error "❌ PersonProfileExtractionWorker: Failed to launch profile extraction for company #{company_id}: #{result.error}"
      raise "Profile extraction launch failed: #{result.error}"
    end
  rescue => e
    Rails.logger.error "❌ PersonProfileExtractionWorker: Critical error for company #{company_id}: #{e.message}"
    raise e
  end
end
