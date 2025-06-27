class PersonProfileExtractionWorker
  include Sidekiq::Worker
  
  sidekiq_options queue: :person_profile_extraction, retry: 2
  
  def perform(company_id)
    Rails.logger.info "🚀 PersonProfileExtractionWorker: Starting profile extraction for company #{company_id}"
    
    service = PersonProfileExtractionService.new(company_id: company_id)
    result = service.call
    
    if result.success?
      Rails.logger.info "✅ PersonProfileExtractionWorker: Successfully extracted profiles for company #{company_id}: #{result.message}"
    else
      Rails.logger.error "❌ PersonProfileExtractionWorker: Failed to extract profiles for company #{company_id}: #{result.error}"
      raise "Profile extraction failed: #{result.error}"
    end
  rescue => e
    Rails.logger.error "❌ PersonProfileExtractionWorker: Critical error for company #{company_id}: #{e.message}"
    raise e
  end
end