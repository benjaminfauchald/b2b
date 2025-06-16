module Webhooks
  class InstantlyWebhookController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :validate_webhook

    def create
      audit_log = ServiceAuditLog.create!(
        service_name: 'instantly_webhook',
        action: 'process_webhook',
        status: :pending,
        context: { payload: webhook_params },
        started_at: Time.current
      )

      begin
        validate_event_type!
        timestamp = parse_timestamp
        communication = create_communication(timestamp)
        
        audit_log.update!(
          status: :success,
          auditable: communication,
          completed_at: Time.current,
          duration_ms: ((Time.current - audit_log.started_at) * 1000).round,
          context: audit_log.context.merge(
            communication_id: communication.id,
            event_type: webhook_params[:event_type],
            campaign_name: webhook_params[:campaign_name]
          )
        )

        render json: { status: 'success', message: 'Webhook processed successfully' }
      rescue StandardError => e
        audit_log.update!(
          status: :failed,
          completed_at: Time.current,
          duration_ms: ((Time.current - audit_log.started_at) * 1000).round,
          error_message: e.message,
          context: audit_log.context.merge(error: e.message)
        )
        raise
      end
    end

    private

    def validate_webhook
      # Add any webhook validation logic here
      # For example, verify signatures, tokens, etc.
    end

    def webhook_params
      params.permit(
        :timestamp,
        :event_type,
        :campaign_name,
        :workspace,
        :campaign_id,
        :lead_email,
        :firstName,
        :lastName,
        :companyName,
        :website,
        :phone,
        :step,
        :email_account
      )
    end

    def validate_event_type!
      return if webhook_params[:event_type].end_with?('_email_sent')
      raise "Invalid event type: #{webhook_params[:event_type]}"
    end

    def parse_timestamp
      Time.parse(webhook_params[:timestamp])
    rescue ArgumentError
      raise "Invalid timestamp format: #{webhook_params[:timestamp]}"
    end

    def create_communication(timestamp)
      Communication.create!(
        source: 'instantly',
        type: 'email',
        status: 'sent',
        sent_at: timestamp,
        recipient_email: webhook_params[:lead_email],
        recipient_name: "#{webhook_params[:firstName]} #{webhook_params[:lastName]}".strip,
        recipient_company: webhook_params[:companyName],
        recipient_website: webhook_params[:website],
        recipient_phone: webhook_params[:phone],
        campaign_name: webhook_params[:campaign_name],
        campaign_id: webhook_params[:campaign_id],
        workspace: webhook_params[:workspace],
        step: webhook_params[:step],
        sender_email: webhook_params[:email_account],
        metadata: {
          event_type: webhook_params[:event_type],
          campaign_name: webhook_params[:campaign_name],
          workspace: webhook_params[:workspace],
          campaign_id: webhook_params[:campaign_id],
          step: webhook_params[:step],
          email_account: webhook_params[:email_account]
        }
      )
    end
  end
end 