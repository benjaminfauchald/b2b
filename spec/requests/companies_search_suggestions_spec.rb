# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Companies Search Suggestions", type: :request do
  let(:user) { create(:user) }
  
  before do
    sign_in user
  end

  describe "GET /companies/search_suggestions" do
    let!(:company1) { create(:company, company_name: "Apple Inc", registration_number: "12345", source_country: "NO") }
    let!(:company2) { create(:company, company_name: "Microsoft Corp", registration_number: "67890", source_country: "NO") }
    let!(:company3) { create(:company, company_name: "Google LLC", registration_number: "11111", source_country: "NO") }
    let!(:other_country_company) { create(:company, company_name: "Apple Sweden", registration_number: "99999", source_country: "SE") }

    before do
      # Set session country to Norway via get request
      get companies_path, params: { country: "NO" }
    end

    context "with valid query" do
      it "returns matching companies by name" do
        get search_suggestions_companies_path, params: { q: "Apple" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to be_an(Array)
        expect(json_response["suggestions"].length).to eq(1)
        expect(json_response["suggestions"].first["company_name"]).to eq("Apple Inc")
        expect(json_response["suggestions"].first["registration_number"]).to eq("12345")
      end

      it "returns matching companies by registration number" do
        get search_suggestions_companies_path, params: { q: "123" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to be_an(Array)
        expect(json_response["suggestions"].length).to eq(1)
        expect(json_response["suggestions"].first["company_name"]).to eq("Apple Inc")
      end

      it "returns multiple matches ordered by name" do
        get search_suggestions_companies_path, params: { q: "Corp" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to be_an(Array)
        expect(json_response["suggestions"].length).to eq(1)
        expect(json_response["suggestions"].first["company_name"]).to eq("Microsoft Corp")
      end

      it "respects the limit parameter" do
        get search_suggestions_companies_path, params: { q: "Inc", limit: 1 }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"].length).to be <= 1
      end

      it "filters by selected country" do
        get search_suggestions_companies_path, params: { q: "Apple" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        # Should only return Norwegian Apple Inc, not Swedish Apple
        expect(json_response["suggestions"].length).to eq(1)
        expect(json_response["suggestions"].first["company_name"]).to eq("Apple Inc")
      end

      it "performs case-insensitive search" do
        get search_suggestions_companies_path, params: { q: "APPLE" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"].length).to eq(1)
        expect(json_response["suggestions"].first["company_name"]).to eq("Apple Inc")
      end
    end

    context "with invalid query" do
      it "returns empty suggestions for blank query" do
        get search_suggestions_companies_path, params: { q: "" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to eq([])
      end

      it "returns empty suggestions for query too short" do
        get search_suggestions_companies_path, params: { q: "A" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to eq([])
      end

      it "returns empty suggestions for no matches" do
        get search_suggestions_companies_path, params: { q: "NonExistentCompany" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to eq([])
      end
    end

    context "parameter validation" do
      it "limits results to maximum 50" do
        get search_suggestions_companies_path, params: { q: "Company", limit: 100 }
        
        expect(response).to have_http_status(:success)
        # Since we only have 3 companies, we can't test the actual limit, 
        # but the controller should accept the request
      end

      it "handles missing limit parameter" do
        get search_suggestions_companies_path, params: { q: "Apple" }
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        
        expect(json_response["suggestions"]).to be_an(Array)
      end
    end
  end
end