# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompaniesController, type: :controller do
  let(:user) { create(:user) }
  
  before do
    sign_in user
    # Enable the LinkedIn discovery service
    ServiceConfiguration.create!(
      service_name: "company_linkedin_discovery",
      active: true
    )
  end

  describe 'POST #queue_linkedin_discovery_by_postal_code' do
    let!(:companies_2000) do
      create_list(:company, 5, postal_code: '2000', operating_revenue: [100_000, 200_000, 300_000, 400_000, 500_000].sample)
    end
    
    let!(:companies_other) do
      create_list(:company, 3, postal_code: '0150', operating_revenue: 100_000)
    end

    context 'when service is active' do
      it 'queues companies for LinkedIn discovery' do
        expect {
          post :queue_linkedin_discovery_by_postal_code, params: {
            postal_code: '2000',
            batch_size: 3
          }
        }.to change { CompanyLinkedinDiscoveryWorker.jobs.size }.by(3)

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['queued_count']).to eq(3)
        expect(json_response['postal_code']).to eq('2000')
        expect(json_response['batch_size']).to eq(3)
      end

      it 'orders companies by operating revenue descending' do
        # Clean up any existing companies first
        Company.where(postal_code: '2000').destroy_all
        
        # Create companies with specific revenues for testing order
        company_high = create(:company, postal_code: '2000', operating_revenue: 1_000_000)
        company_medium = create(:company, postal_code: '2000', operating_revenue: 500_000)
        company_low = create(:company, postal_code: '2000', operating_revenue: 100_000)

        # Clear any existing jobs
        CompanyLinkedinDiscoveryWorker.clear

        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '2000',
          batch_size: 2
        }

        # Check that the jobs were created for the highest revenue companies
        company_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |job| job['args'].first }
        expect(company_ids).to include(company_high.id, company_medium.id)
        expect(company_ids).not_to include(company_low.id)
      end

      it 'validates postal code is provided' do
        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '',
          batch_size: 10
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to eq('Postal code is required')
      end

      it 'validates batch size is positive' do
        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '2000',
          batch_size: 0
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to eq('Batch size must be greater than 0')
      end

      it 'validates batch size is not too large' do
        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '2000',
          batch_size: 1001
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to eq('Cannot queue more than 1000 companies at once')
      end

      it 'handles postal code with no companies' do
        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '9999',
          batch_size: 10
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to match(/No companies found in postal code 9999/)
        expect(json_response['available_count']).to eq(0)
      end

      it 'handles batch size larger than available companies' do
        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '2000',
          batch_size: 100
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to match(/Only \d+ companies available/)
      end

      it 'defaults batch size to 100 when not provided' do
        # Create enough companies so batch size 100 will work
        Company.where(postal_code: '2000').destroy_all
        create_list(:company, 150, postal_code: '2000', operating_revenue: 100_000)

        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '2000'
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['batch_size']).to eq(100)
        expect(json_response['queued_count']).to eq(100)
      end
    end

    context 'when service is disabled' do
      before do
        ServiceConfiguration.find_by(service_name: "company_linkedin_discovery")&.update!(active: false)
      end

      it 'returns error when service is disabled' do
        post :queue_linkedin_discovery_by_postal_code, params: {
          postal_code: '2000',
          batch_size: 10
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to eq('LinkedIn discovery service is disabled')
      end
    end
  end

  describe 'GET #postal_code_preview' do
    let!(:companies_2000) do
      [
        create(:company, postal_code: '2000', operating_revenue: 1_000_000),
        create(:company, postal_code: '2000', operating_revenue: 500_000),
        create(:company, postal_code: '2000', operating_revenue: 100_000)
      ]
    end

    it 'returns preview data for postal code' do
      get :postal_code_preview, params: {
        postal_code: '2000',
        batch_size: 2
      }

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['count']).to eq(3)
      expect(json_response['postal_code']).to eq('2000')
      expect(json_response['batch_size']).to eq(2)
      expect(json_response['revenue_range']).to be_present
      expect(json_response['revenue_range']['highest']).to eq('1.0M NOK')
      expect(json_response['revenue_range']['lowest']).to eq('500K NOK')
    end

    it 'handles empty postal code' do
      get :postal_code_preview, params: {
        postal_code: '',
        batch_size: 10
      }

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['count']).to eq(0)
      expect(json_response['revenue_range']).to be_nil
    end

    it 'defaults batch size to 100' do
      get :postal_code_preview, params: {
        postal_code: '2000'
      }

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['batch_size']).to eq(100)
    end

    it 'handles postal code with no companies' do
      get :postal_code_preview, params: {
        postal_code: '9999',
        batch_size: 10
      }

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['count']).to eq(0)
      expect(json_response['revenue_range']).to be_nil
    end
  end
end