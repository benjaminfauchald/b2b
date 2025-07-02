class PersonEmailExtractionWorker
  include Sidekiq::Worker

  sidekiq_options queue: :person_email_extraction, retry: 2

  def perform(person_id)
    Rails.logger.info "🚀 PersonEmailExtractionWorker: Starting email extraction for person #{person_id}"

    service = PersonEmailExtractionService.new(person_id: person_id)
    result = service.perform

    if result.success?
      Rails.logger.info "✅ PersonEmailExtractionWorker: Email extraction completed for person #{person_id}: #{result.message}"
    else
      Rails.logger.error "❌ PersonEmailExtractionWorker: Failed to extract email for person #{person_id}: #{result.error}"
      raise "Email extraction failed: #{result.error}"
    end
  rescue => e
    Rails.logger.error "❌ PersonEmailExtractionWorker: Critical error for person #{person_id}: #{e.message}"
    raise e
  end
end
