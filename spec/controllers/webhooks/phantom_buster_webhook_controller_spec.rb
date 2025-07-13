require 'rails_helper'

RSpec.describe Webhooks::PhantomBusterWebhookController, type: :controller do
  describe 'POST #profile_extraction' do
    let(:valid_payload) do
      {
        containerId: 'test-container-123',
        status: 'finished',
        progress: 100,
        resultUrl: 'https://phantombuster.s3.amazonaws.com/result.csv',
        startedAt: '2024-01-01T10:00:00Z',
        finishedAt: '2024-01-01T10:30:00Z',
        duration: 1800
      }
    end

    let(:webhook_secret) { 'test-secret-key' }
    
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('PHANTOMBUSTER_WEBHOOK_SECRET').and_return(webhook_secret)
    end

    context 'with valid signature' do
      before do
        payload_json = valid_payload.to_json
        signature = OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha256'),
          webhook_secret,
          payload_json
        )
        
        request.headers['X-PhantomBuster-Signature'] = "sha256=#{signature}"
        request.headers['Content-Type'] = 'application/json'
        
        # Mock request body
        allow(request).to receive(:body).and_return(StringIO.new(payload_json))
      end

      it 'creates a service audit log' do
        expect {
          post :profile_extraction, params: valid_payload, format: :json
        }.to change(ServiceAuditLog, :count).by(1)
        
        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('phantom_buster_webhook')
        expect(audit_log.operation_type).to eq('process_webhook')
        expect(audit_log.status).to eq('success')
        expect(audit_log.metadata['phantom_container_id']).to eq('test-container-123')
        expect(audit_log.metadata['phantom_status']).to eq('finished')
      end

      it 'queues the webhook processing job' do
        expect(PhantomBusterWebhookJob).to receive(:perform_async).with(
          hash_including('containerId' => 'test-container-123'),
          kind_of(Integer)
        )
        
        post :profile_extraction, params: valid_payload, format: :json
      end

      it 'returns success response' do
        allow(PhantomBusterWebhookJob).to receive(:perform_async)
        
        post :profile_extraction, params: valid_payload, format: :json
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['message']).to eq('Webhook received and queued for processing')
        expect(json_response['container_id']).to eq('test-container-123')
      end
    end

    context 'with invalid signature' do
      before do
        request.headers['X-PhantomBuster-Signature'] = 'invalid-signature'
        request.headers['Content-Type'] = 'application/json'
        allow(request).to receive(:body).and_return(StringIO.new(valid_payload.to_json))
      end

      it 'returns unauthorized status' do
        post :profile_extraction, params: valid_payload, format: :json
        
        expect(response).to have_http_status(:unauthorized)
        
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Unauthorized')
      end

      it 'does not create audit log' do
        expect {
          post :profile_extraction, params: valid_payload, format: :json
        }.not_to change(ServiceAuditLog, :count)
      end
    end

    context 'with missing signature' do
      before do
        request.headers['Content-Type'] = 'application/json'
        allow(request).to receive(:body).and_return(StringIO.new(valid_payload.to_json))
      end

      it 'returns unauthorized status' do
        post :profile_extraction, params: valid_payload, format: :json
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid payload' do
      let(:invalid_payload) { { status: 'finished' } } # missing containerId
      
      before do
        payload_json = invalid_payload.to_json
        signature = OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha256'),
          webhook_secret,
          payload_json
        )
        
        request.headers['X-PhantomBuster-Signature'] = "sha256=#{signature}"
        request.headers['Content-Type'] = 'application/json'
        allow(request).to receive(:body).and_return(StringIO.new(payload_json))
      end

      it 'returns bad request status' do
        post :profile_extraction, params: invalid_payload, format: :json
        
        expect(response).to have_http_status(:bad_request)
        
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to include('Missing container ID')
      end

      it 'creates failed audit log' do
        expect {
          post :profile_extraction, params: invalid_payload, format: :json
        }.to change(ServiceAuditLog, :count).by(1)
        
        audit_log = ServiceAuditLog.last
        expect(audit_log.status).to eq('failed')
        expect(audit_log.error_message).to include('Missing container ID')
      end
    end

    context 'without webhook secret configured' do
      before do
        allow(ENV).to receive(:[]).with('PHANTOMBUSTER_WEBHOOK_SECRET').and_return(nil)
        request.headers['Content-Type'] = 'application/json'
        allow(request).to receive(:body).and_return(StringIO.new(valid_payload.to_json))
      end

      it 'skips signature validation and processes request' do
        allow(PhantomBusterWebhookJob).to receive(:perform_async)
        
        post :profile_extraction, params: valid_payload, format: :json
        
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'status validation' do
      let(:webhook_secret) { 'test-secret' }
      
      before do
        allow(ENV).to receive(:[]).with('PHANTOMBUSTER_WEBHOOK_SECRET').and_return(webhook_secret)
      end
      
      ['running', 'finished', 'error'].each do |status|
        context "with status '#{status}'" do
          let(:test_payload) { valid_payload.merge(status: status) }
          
          before do
            payload_json = test_payload.to_json
            signature = OpenSSL::HMAC.hexdigest(
              OpenSSL::Digest.new('sha256'),
              webhook_secret,
              payload_json
            )
            
            request.headers['X-PhantomBuster-Signature'] = "sha256=#{signature}"
            request.headers['Content-Type'] = 'application/json'
            allow(request).to receive(:body).and_return(StringIO.new(payload_json))
          end

          it 'accepts the status' do
            allow(PhantomBusterWebhookJob).to receive(:perform_async)
            
            post :profile_extraction, params: test_payload, format: :json
            
            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'with invalid status' do
        let(:invalid_status_payload) { valid_payload.merge(status: 'unknown') }
        
        before do
          payload_json = invalid_status_payload.to_json
          signature = OpenSSL::HMAC.hexdigest(
            OpenSSL::Digest.new('sha256'),
            webhook_secret,
            payload_json
          )
          
          request.headers['X-PhantomBuster-Signature'] = "sha256=#{signature}"
          request.headers['Content-Type'] = 'application/json'
          allow(request).to receive(:body).and_return(StringIO.new(payload_json))
        end

        it 'returns bad request' do
          post :profile_extraction, params: invalid_status_payload, format: :json
          
          expect(response).to have_http_status(:bad_request)
          
          json_response = JSON.parse(response.body)
          expect(json_response['message']).to include('Invalid status: unknown')
        end
      end
    end
  end
end