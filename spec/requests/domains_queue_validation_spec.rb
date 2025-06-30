require 'rails_helper'

RSpec.describe 'Domain Queue Validation', type: :request do
  let(:user) { FactoryBot.create(:user, role: 'admin') }

  before do
    # Skip authentication for these API tests
    allow_any_instance_of(DomainsController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(DomainsController).to receive(:current_user).and_return(user)

    # Enable service configurations
    ServiceConfiguration.create!(
      service_name: 'domain_testing',
      active: true,
      refresh_interval_hours: 24
    )

    ServiceConfiguration.create!(
      service_name: 'domain_mx_testing',
      active: true,
      refresh_interval_hours: 24
    )

    ServiceConfiguration.create!(
      service_name: 'domain_a_record_testing',
      active: true,
      refresh_interval_hours: 24
    )
  end

  describe 'DNS Testing Queue Validation' do
    context 'when requesting more domains than available' do
      before do
        # Create only 5 domains that need testing
        5.times { FactoryBot.create(:domain) }
      end

      it 'queues all available domains when requesting more than available' do
        post '/domains/queue_dns_testing', params: { count: 10 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_truthy
        expect(json['queued_count']).to eq(5)
        expect(json['message']).to include('available domains for DNS testing')
      end

      it 'allows queueing exact number of available domains' do
        post '/domains/queue_dns_testing', params: { count: 5 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_truthy
        expect(json['queued_count']).to eq(5)
        expect(json['available_count']).to eq(5)
      end

      it 'allows queueing fewer domains than available' do
        post '/domains/queue_dns_testing', params: { count: 3 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_truthy
        expect(json['queued_count']).to eq(3)
        expect(json['available_count']).to eq(5)
      end
    end

    context 'when no domains need testing' do
      it 'returns appropriate error message' do
        post '/domains/queue_dns_testing', params: { count: 1 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_falsey
        expect(json['message']).to include('No domains need DNS testing')
        expect(json['available_count']).to eq(0)
      end
    end

    context 'with invalid count parameters' do
      before do
        FactoryBot.create(:domain)
      end

      it 'rejects zero count' do
        post '/domains/queue_dns_testing', params: { count: 0 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_falsey
        expect(json['message']).to eq('Count must be greater than 0')
      end

      it 'rejects negative count' do
        post '/domains/queue_dns_testing', params: { count: -5 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_falsey
        expect(json['message']).to eq('Count must be greater than 0')
      end

      it 'rejects count over 1000' do
        post '/domains/queue_dns_testing', params: { count: 1001 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_falsey
        expect(json['message']).to eq('Cannot queue more than 1000 domains at once')
      end
    end
  end

  describe 'MX Testing Queue Validation' do
    context 'when requesting more domains than available' do
      before do
        # Create domains that need MX testing (dns: true, www: true, mx: nil)
        3.times { FactoryBot.create(:domain, dns: true, www: true, mx: nil) }
      end

      it 'queues all available domains when requesting more than available' do
        post '/domains/queue_mx_testing', params: { count: 5 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_truthy
        expect(json['queued_count']).to eq(3)
        expect(json['message']).to include('available domains for MX testing')
      end
    end
  end

  describe 'A Record Testing Queue Validation' do
    context 'when requesting more domains than available' do
      before do
        # Create domains that need A record testing (dns: true, www: nil)
        2.times { FactoryBot.create(:domain, dns: true, www: nil) }
      end

      it 'queues all available domains when requesting more than available' do
        post '/domains/queue_a_record_testing', params: { count: 5 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be_truthy
        expect(json['queued_count']).to eq(2)
        expect(json['message']).to include('available domains for A Record testing')
      end
    end
  end
end
