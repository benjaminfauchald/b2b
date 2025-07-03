# frozen_string_literal: true

# Worker to monitor and timeout stuck PhantomBuster jobs
class PhantomJobMonitorWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 3

  # Maximum time to wait for a PhantomBuster job before timing out
  PHANTOM_TIMEOUT_MINUTES = 10

  def perform
    check_stuck_phantom_jobs
  end

  private

  def check_stuck_phantom_jobs
    # Find all pending phantom jobs older than timeout threshold
    stuck_jobs = ServiceAuditLog.where(
      service_name: "person_profile_extraction_async",
      status: "pending"
    ).where("started_at < ?", PHANTOM_TIMEOUT_MINUTES.minutes.ago)

    Rails.logger.info "PhantomJobMonitor: Found #{stuck_jobs.count} stuck jobs"

    stuck_jobs.find_each do |audit_log|
      timeout_phantom_job(audit_log)
    end
  end

  def timeout_phantom_job(audit_log)
    Rails.logger.warn "PhantomJobMonitor: Timing out job #{audit_log.id} for #{audit_log.auditable&.company_name}"

    # Update metadata to include error
    updated_metadata = audit_log.metadata.merge(
      "error" => "PhantomBuster job timed out after #{PHANTOM_TIMEOUT_MINUTES} minutes",
      "timeout_reason" => "No status updates received within timeout period",
      "timeout_at" => Time.current.iso8601,
      "monitor_timeout" => true
    )

    # Mark as failed
    audit_log.update!(
      status: "failed",
      completed_at: Time.current,
      error_message: "PhantomBuster job timed out after #{PHANTOM_TIMEOUT_MINUTES} minutes",
      execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
      metadata: updated_metadata
    )

    # Log for monitoring
    Rails.logger.error "PhantomJobMonitor: Timed out phantom job #{audit_log.id} - Container: #{audit_log.metadata['container_id']}"
  rescue => e
    Rails.logger.error "PhantomJobMonitor: Error timing out job #{audit_log.id}: #{e.message}"
  end
end
