module Webhooks
  class InstantlyWebhookController < ActionController::API
    def create
      payload = JSON.parse(request.body.read)
      if payload['event_type'].end_with?('_email_sent')
        communication = Communication.new(
          timestamp: payload['timestamp'],
          event_type: payload['event_type'],
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
          render json: { status: 'success' }, status: :ok
        else
          render json: { errors: communication.errors.full_messages }, status: :unprocessable_entity
        end
      else
        render json: { error: 'Invalid event type' }, status: :bad_request
      end
    end
  end
end 