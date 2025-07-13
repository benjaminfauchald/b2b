module Webhooks
  class PhantomBusterWebhookController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    before_action :validate_webhook_signature

    def profile_extraction
      # Log the webhook for debugging
      Rails.logger.info "PhantomBuster webhook received for profile extraction"
      Rails.logger.info "Params: #{params.inspect}"
      
      # Create audit log without auditable - we'll find it later from container ID
      # Use a dummy company for now to satisfy the not-null constraint
      dummy_company = Company.first || Company.new(id: 0)
      
      audit_log = ServiceAuditLog.create!(
        auditable: dummy_company,  # Temporary - will be updated by webhook job
        auditable_type: "Company",
        auditable_id: dummy_company.id,
        service_name: "phantom_buster_webhook",
        operation_type: "process_webhook",
        status: :pending,
        table_name: "phantom_buster_webhooks",
        record_id: SecureRandom.uuid,
        columns_affected: ["payload"],
        started_at: Time.current,
        metadata: {
          webhook_payload: params.to_unsafe_h,
          headers: request.headers.to_h.select { |k, v| k.start_with?("HTTP_") },
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          phantom_container_id: webhook_params[:containerId],
          phantom_status: webhook_params[:status] || webhook_params[:exitMessage],
          temp_auditable: true  # Mark this as temporary
        }
      )

      begin
        validate_webhook_payload!
        
        # Queue async processing job
        PhantomBusterWebhookJob.perform_later(
          webhook_params.to_h,
          audit_log.id
        )

        audit_log.update!(
          status: :success,
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
          metadata: audit_log.metadata.merge(
            container_id: webhook_params[:containerId],
            status: webhook_params[:status],
            job_queued: true
          )
        )

        render json: { 
          status: "success", 
          message: "Webhook received and queued for processing",
          container_id: webhook_params[:containerId]
        }
      rescue StandardError => e
        audit_log.update!(
          status: :failed,
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
          error_message: e.message,
          metadata: audit_log.metadata.merge(error: e.message)
        )
        
        Rails.logger.error "PhantomBuster webhook processing failed: #{e.message}"
        render json: { 
          status: "error", 
          message: "Webhook processing failed: #{e.message}" 
        }, status: 400
      end
    end

    private

    def validate_webhook_signature
      # PhantomBuster webhook signature verification
      # TODO: Implement proper webhook authentication once we know PhantomBuster's format
      
      # For now, log the webhook attempt
      Rails.logger.info "PhantomBuster webhook received"
      Rails.logger.info "Headers: #{request.headers.to_h.select { |k, v| k.start_with?('HTTP_') }.inspect}"
      
      # Temporarily skip validation to test webhook functionality
      return
      
      # Original validation code (disabled for testing):
      # signature = request.headers['X-PhantomBuster-Signature']
      # webhook_secret = ENV['PHANTOMBUSTER_WEBHOOK_SECRET']
      # ...
    end

    def webhook_params
      params.permit(
        :containerId,
        :status,
        :exitMessage,
        :exitCode,
        :progress,
        :resultUrl,
        :resultObject,
        :error,
        :message,
        :startedAt,
        :finishedAt,
        :duration,
        :runDuration,
        :launchDuration,
        :agentId,
        :agentName,
        :script,
        :scriptOrg,
        :branch,
        data: {}
      )
    end

    def validate_webhook_payload!
      # Validate required fields
      raise "Missing container ID" if webhook_params[:containerId].blank?
      
      # PhantomBuster sends either 'status' or 'exitMessage' depending on the event
      status = webhook_params[:status] || webhook_params[:exitMessage]
      raise "Missing status or exitMessage" if status.blank?
      
      # Normalize status values
      valid_statuses = %w[running finished error]
      unless valid_statuses.include?(status)
        # PhantomBuster might send different values, normalize them
        if status == 'finished' || webhook_params[:exitCode] == 0
          # Job completed successfully
        else
          Rails.logger.warn "Unknown status: #{status}"
        end
      end
    end
  end
end