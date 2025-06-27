class PersonSocialMediaExtractionWorker
  include Sidekiq::Worker
  
  sidekiq_options queue: :person_social_media_extraction, retry: 2
  
  def perform(person_id)
    Rails.logger.info "🚀 PersonSocialMediaExtractionWorker: Starting social media extraction for person #{person_id}"
    
    service = PersonSocialMediaExtractionService.new(person_id: person_id)
    result = service.call
    
    if result.success?
      Rails.logger.info "✅ PersonSocialMediaExtractionWorker: Social media extraction completed for person #{person_id}: #{result.message}"
    else
      Rails.logger.error "❌ PersonSocialMediaExtractionWorker: Failed to extract social media for person #{person_id}: #{result.error}"
      raise "Social media extraction failed: #{result.error}"
    end
  rescue => e
    Rails.logger.error "❌ PersonSocialMediaExtractionWorker: Critical error for person #{person_id}: #{e.message}"
    raise e
  end
end