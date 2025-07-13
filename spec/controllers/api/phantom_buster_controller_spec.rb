# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PhantomBusterController, type: :controller do
  let(:user) { create(:user) }
  
  before do
    sign_in user
  end

  describe "GET #status" do
    context "when PhantomBuster is not processing" do
      before do
        allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
          queue_length: 0,
          is_processing: false,
          current_job: nil,
          lock_timestamp: Time.current.to_i
        })
      end

      it "returns idle status" do
        get :status, format: :json
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response['is_processing']).to be false
        expect(json_response['queue_length']).to eq(0)
        expect(json_response['current_company']).to be_nil
      end
    end

    context "when PhantomBuster is processing a company" do
      let(:company) { create(:company, company_name: "Test Company AS") }
      
      before do
        allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
          queue_length: 2,
          is_processing: true,
          current_job: {
            'company_id' => company.id,
            'queued_at' => 2.minutes.ago.to_i
          },
          lock_timestamp: Time.current.to_i
        })
      end

      it "returns processing status with company details" do
        get :status, format: :json
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response['is_processing']).to be true
        expect(json_response['queue_length']).to eq(2)
        expect(json_response['current_company']).to eq("Test Company AS")
        expect(json_response['current_company_id']).to eq(company.id)
        expect(json_response['current_job_duration']).to be_present
        expect(json_response['estimated_completion']).to be_present
      end
    end

    context "when PhantomBusterSequentialQueue raises an error" do
      before do
        allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_raise(StandardError.new("Redis connection failed"))
      end

      it "returns error response" do
        get :status, format: :json
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        
        expect(json_response['is_processing']).to be false
        expect(json_response['queue_length']).to eq(0)
        expect(json_response['error']).to eq('Unable to fetch status')
      end
    end
  end

  describe "authentication" do
    context "when user is not authenticated" do
      before do
        sign_out user
      end

      it "requires authentication" do
        get :status, format: :json
        
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end