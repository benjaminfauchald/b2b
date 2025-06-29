class PersonProfileExtractionStatusWorker
  include Sidekiq::Worker

  sidekiq_options queue: :person_profile_extraction, retry: 3

  def perform(company_id, container_id, audit_log_id)
    Rails.logger.info "🔍 PersonProfileExtractionStatusWorker: Checking status for container #{container_id}"

    service = PersonProfileExtractionServiceV2.new(company_id: company_id)
    result = service.check_phantom_status(container_id, audit_log_id)

    if result.success?
      if result.data[:status] == "running"
        Rails.logger.info "⏳ Container still running, will check again..."
      else
        Rails.logger.info "✅ Profile extraction check completed: #{result.message}"
      end
    else
      Rails.logger.error "❌ Profile extraction status check failed: #{result.error}"
      # Don't raise error - we've already logged it in the audit log
    end
  rescue => e
    Rails.logger.error "❌ PersonProfileExtractionStatusWorker: Critical error: #{e.message}"
    # Update audit log to failed state
    begin
      audit_log = ServiceAuditLog.find(audit_log_id)
      audit_log.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: "Worker error: #{e.message}"
      )
    rescue => log_error
      Rails.logger.error "Failed to update audit log: #{log_error.message}"
    end
    raise e
  end
end
