class PersonProfileExtractionWorker
  include Sidekiq::Worker

  sidekiq_options queue: :person_profile_extraction, retry: 2

  def perform(company_id, options = {})
    Rails.logger.info "🚀 PersonProfileExtractionWorker: Starting profile extraction for company #{company_id}"
    
    # Check if we're in webhook mode
    webhook_mode = options.is_a?(Hash) && options['webhook_mode']
    webhook_url = options['webhook_url'] if webhook_mode
    queue_job_id = options['queue_job_id'] if webhook_mode
    
    if webhook_mode
      Rails.logger.info "🔗 Using webhook mode with URL: #{webhook_url}"
      service = PersonProfileExtractionWebhookService.new(
        company_id: company_id,
        webhook_url: webhook_url,
        queue_job_id: queue_job_id
      )
    else
      Rails.logger.info "📊 Using polling mode (legacy)"
      service = PersonProfileExtractionAsyncService.new(company_id: company_id)
    end
    
    result = service.call

    if result.success?
      Rails.logger.info "✅ PersonProfileExtractionWorker: Profile extraction launched for company #{company_id}: #{result.message}"
      # The service now handles async monitoring, so we just return success
    else
      Rails.logger.error "❌ PersonProfileExtractionWorker: Failed to launch profile extraction for company #{company_id}: #{result.error}"
      
      if webhook_mode
        # In webhook mode, we need to notify the sequential queue about the failure
        PhantomBusterSequentialQueue.job_completed(nil, 'failed')
      end
      
      raise "Profile extraction launch failed: #{result.error}"
    end
  rescue => e
    Rails.logger.error "❌ PersonProfileExtractionWorker: Critical error for company #{company_id}: #{e.message}"
    
    if options.is_a?(Hash) && options['webhook_mode']
      # In webhook mode, notify queue about failure
      PhantomBusterSequentialQueue.job_completed(nil, 'failed')
    end
    
    raise e
  end
end
