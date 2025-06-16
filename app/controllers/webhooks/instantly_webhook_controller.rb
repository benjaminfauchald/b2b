module Webhooks
  class InstantlyWebhookController < ActionController::API
    def create
      begin
        payload = JSON.parse(request.body.read)
        Rails.logger.info("Received Instantly webhook: #{payload.inspect}")

        event_type = payload['event_type']
        unless event_type.present? && event_type.end_with?('_email_sent')
          return render json: { error: 'Invalid event type' }, status: :bad_request
        end

        timestamp = begin
          Time.parse(payload['timestamp'])
        rescue
          nil
        end

        communication = Communication.new(
          timestamp: timestamp,
          event_type: event_type,
          campaign_name: payload['campaign_name'],
          workspace: payload['workspace'],
          campaign_id: payload['campaign_id'],
          service: 'instantly',
          connection_attempt_type: 'email',
          lead_email: payload['lead_email'],
          first_name: payload['firstName'],
          last_name: payload['lastName'],
          company_name: payload['companyName'],
          website: payload['website'],
          phone: payload['phone'],
          step: payload['step'],
          email_account: payload['email_account']
        )

        if communication.save
          # Create audit log after successful communication save
          ServiceAuditLog.create!(
            service_name: 'instantly_webhook',
            action: 'process_webhook',
            status: :success,
            auditable: communication,
            context: {
              event_type: event_type,
              campaign_id: payload['campaign_id'],
              lead_email: payload['lead_email']
            }
          )
          render json: { status: 'success' }, status: :ok
        else
          # Create audit log for failed communication
          ServiceAuditLog.create!(
            service_name: 'instantly_webhook',
            action: 'process_webhook',
            status: :failed,
            error_message: communication.errors.full_messages.join(', '),
            context: {
              event_type: event_type,
              campaign_id: payload['campaign_id'],
              lead_email: payload['lead_email'],
              errors: communication.errors.full_messages
            }
          )
          render json: { errors: communication.errors.full_messages }, status: :unprocessable_entity
        end
      rescue JSON::ParserError => e
        ServiceAuditLog.create!(
          service_name: 'instantly_webhook',
          action: 'process_webhook',
          status: :failed,
          error_message: "Invalid JSON payload: #{e.message}",
          context: { raw_body: request.body.read }
        )
        render json: { error: 'Invalid JSON payload' }, status: :bad_request
      rescue StandardError => e
        ServiceAuditLog.create!(
          service_name: 'instantly_webhook',
          action: 'process_webhook',
          status: :failed,
          error_message: e.message,
          context: {
            error_class: e.class.name,
            backtrace: e.backtrace.first(5)
          }
        )
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end
    end
  end
end 