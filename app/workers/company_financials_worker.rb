class CompanyFinancialsWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'financials', retry: 5, backtrace: true

  sidekiq_retries_exhausted do |msg, ex|
    company_id = msg['args'].first
    company = Company.find_by(id: company_id)
    
    if company
      # Log to SCT
      log_to_sct('WORKER_RETRIES_EXHAUSTED', [], 'FAILED', 0, ex.message, {
        company_id: company_id,
        registration_number: company.registration_number,
        error_class: ex.class.name,
        retry_count: msg['retry_count']
      })
    end
  end

  sidekiq_retry_in do |count, exception|
    case exception
    when CompanyFinancialsService::RateLimitError
      # Use retry_after from the exception or default to exponential backoff
      (exception.retry_after || 10 * (count + 1)).to_i
    else
      # Exponential backoff for other errors
      10 * (count + 1)
    end
  end

  def perform(company_id, enqueued_at = nil)
    @start_time = Time.current
    @company = Company.find_by(id: company_id)
    
    unless @company
      log_to_sct('COMPANY_NOT_FOUND', [], 'FAILED', 0, "Company not found: #{company_id}", { company_id: company_id })
      return
    end

    log_to_sct('WORKER_START', [], 'PENDING', 0, nil, {
      company_id: @company.id,
      registration_number: @company.registration_number,
      queue_latency_ms: enqueued_at ? ((@start_time - Time.at(enqueued_at)) * 1000).round : nil
    })

    CompanyFinancialsService.new(@company).call
    
    log_to_sct('WORKER_COMPLETE', [], 'SUCCESS', 
      ((Time.current - @start_time) * 1000).round, 
      nil,
      { company_id: @company.id, registration_number: @company.registration_number }
    )
  rescue => e
    log_to_sct('WORKER_ERROR', [], 'FAILED', 
      ((Time.current - @start_time) * 1000).round, 
      e.message,
      {
        company_id: @company&.id,
        registration_number: @company&.registration_number,
        error_class: e.class.name,
        backtrace: e.backtrace.first(5)
      }
    )
    raise # Re-raise to trigger Sidekiq's retry mechanism
  end
  
  private
  
  def log_to_sct(action, fields, status, duration_ms, error_message = nil, metadata = {})
    begin
      # Replace with your actual SCT logging implementation
      Rails.logger.info("[SCT] #{action} - #{status} - #{error_message}")
      Rails.logger.debug("[SCT] Metadata: #{metadata.to_json}")
    rescue => e
      Rails.logger.error("Failed to log to SCT in worker: #{e.message}")
    end
  end
end
