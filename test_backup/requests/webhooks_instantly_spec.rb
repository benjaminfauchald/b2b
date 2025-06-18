require 'rails_helper'

describe 'Instantly Webhook', type: :request do
  let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }
  let(:url) { '/webhooks/instantly' }

  let(:valid_payload) do
    {
      'event_type' => 'campaign_email_sent',
      'timestamp' => Time.now.to_i,
      'campaign_name' => 'Test Campaign',
      'workspace' => 'Test Workspace',
      'campaign_id' => '123',
      'lead_email' => 'test@example.com',
      'firstName' => 'John',
      'lastName' => 'Doe',
      'companyName' => 'Test Company',
      'website' => 'https://example.com',
      'phone' => '1234567890',
      'step' => 'Step 1',
      'email_account' => 'account@example.com'
    }
  end

  it 'logs and processes a valid email sent event' do
    expect {
      post url, params: valid_payload.to_json, headers: headers
    }.to change { Communication.count }.by(1)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['status']).to eq('success')
    comm = Communication.last
    expect(comm.event_type).to eq('campaign_email_sent')
    expect(comm.lead_email).to eq('test@example.com')
  end

  it 'returns error for invalid event type' do
    payload = valid_payload.merge('event_type' => 'not_supported')
    expect {
      post url, params: payload.to_json, headers: headers
    }.not_to change { Communication.count }
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)['error']).to eq('Invalid event type')
  end

  it 'returns error for missing required fields' do
    payload = valid_payload.except('event_type')
    expect {
      post url, params: payload.to_json, headers: headers
    }.not_to change { Communication.count }
    expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_entity)
  end
end
