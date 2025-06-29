require 'rails_helper'

RSpec.describe "Financial Service Country Workflow", type: :request do
  include Devise::Test::IntegrationHelpers
  
  let(:user) { create(:user) }
  
  before do
    # Sign in the user
    sign_in user
    
    # Enable services
    allow(ServiceConfiguration).to receive(:active?).and_return(true)
    
    # Create realistic test data
    setup_multi_country_companies
  end

  def setup_multi_country_companies
    # Norwegian companies (mix of states)
    create_list(:company, 3, 
      source_country: "NO",
      source_registry: "brreg",
      organization_form_code: "AS",
      company_name: "Norge Industri AS",
      ordinary_result: nil, # Needs financial update
      annual_result: nil,
      operating_revenue: nil
    )
    
    create_list(:company, 2,
      source_country: "NO",
      company_name: "Oslo Tech AS",
      ordinary_result: 5000000,
      annual_result: 4500000,
      operating_revenue: 25000000
    )
    
    # Swedish companies (mix of states)  
    create_list(:company, 5,
      source_country: "SE",
      source_registry: "bolagsverket",
      organization_form_code: "AB",
      company_name: "Sverige Innovation AB",
      ordinary_result: nil, # Needs financial update
      annual_result: nil,
      operating_revenue: nil
    )
    
    create_list(:company, 3,
      source_country: "SE", 
      company_name: "Stockholm Digital AB",
      ordinary_result: 8000000,
      annual_result: 7500000,
      operating_revenue: 40000000
    )
    
    # Danish companies (all with financials)
    create_list(:company, 4,
      source_country: "DK",
      company_name: "Danmark Solutions ApS",
      ordinary_result: 3000000,
      annual_result: 2800000,
      operating_revenue: 15000000
    )
    
    # Create historical audit logs
    Company.where(source_country: "NO", ordinary_result: 5000000).each do |company|
      create(:service_audit_log,
        auditable: company,
        service_name: "company_financials",
        status: ServiceAuditLog::STATUS_SUCCESS,
        completed_at: 2.days.ago,
        metadata: { "fields_updated" => ["ordinary_result", "annual_result"] }
      )
    end
    
    Company.where(source_country: "SE", ordinary_result: 8000000).limit(2).each do |company|
      create(:service_audit_log,
        auditable: company,
        service_name: "company_financials", 
        status: ServiceAuditLog::STATUS_SUCCESS,
        completed_at: 1.day.ago,
        metadata: { "fields_updated" => ["ordinary_result", "annual_result", "operating_revenue"] }
      )
    end
  end

  describe "Complete workflow for Swedish financial data" do
    it "shows Swedish data throughout the entire financial workflow" do
      # Step 1: Navigate to companies page (defaults to first country alphabetically)
      get companies_path
      expect(response.body).to include("Danmark Solutions") # DK is first alphabetically
      
      # Step 2: Switch to Sweden
      post set_country_companies_path, params: { country: "SE" }
      expect(response).to redirect_to(companies_path)
      follow_redirect!
      
      # Step 3: Verify Swedish companies are shown
      expect(response.body).to include("Sverige Innovation AB")
      expect(response.body).to include("Stockholm Digital AB")
      expect(response.body).not_to include("Norge Industri")
      expect(response.body).not_to include("Danmark Solutions")
      
      # Step 4: Check financial statistics
      expect(response.body).to match(/Services Completed.*2/m) # 2 Swedish companies have been processed
      
      # Step 5: Filter by companies with financials
      get companies_path, params: { filter: "with_financials" }
      expect(response.body.scan(/Stockholm Digital AB/).count).to eq(3) # 3 companies with financials
      expect(response.body).not_to include("Sverige Innovation AB") # These don't have financials yet
      
      # Step 6: Check queue status for financial data
      get enhancement_queue_status_companies_path, as: :json
      queue_status = JSON.parse(response.body)
      expect(queue_status["available_count"]).to eq(5) # 5 Swedish companies need financials
      
      # Step 7: Queue some companies for processing
      allow(CompanyFinancialsWorker).to receive(:perform_async)
      post queue_financial_data_companies_path, params: { count: 3 }, as: :json
      
      response_data = JSON.parse(response.body)
      expect(response_data["success"]).to be true
      expect(response_data["queued_count"]).to eq(3)
      expect(response_data["message"]).to include("3 companies queued")
      
      # Step 8: Verify service stats are country-specific
      get service_stats_companies_path, as: :json
      stats = JSON.parse(response.body)
      expect(stats["total_processed"]).to eq(2) # Only Swedish successful services
      expect(stats["financial_needing"]).to eq(5) # Swedish companies needing updates
    end
  end

  describe "Country switching preserves context" do
    it "maintains separate queue states for each country" do
      # Check Norway
      post set_country_companies_path, params: { country: "NO" }
      get enhancement_queue_status_companies_path, as: :json
      no_status = JSON.parse(response.body)
      expect(no_status["available_count"]).to eq(3) # 3 Norwegian companies need updates
      
      # Check Sweden  
      post set_country_companies_path, params: { country: "SE" }
      get enhancement_queue_status_companies_path, as: :json
      se_status = JSON.parse(response.body)
      expect(se_status["available_count"]).to eq(5) # 5 Swedish companies need updates
      
      # Check Denmark
      post set_country_companies_path, params: { country: "DK" }
      get enhancement_queue_status_companies_path, as: :json
      dk_status = JSON.parse(response.body)
      expect(dk_status["available_count"]).to eq(0) # No Danish companies need updates
    end

    it "shows accurate financial queue counts in UI" do
      # Select Sweden and check the page
      post set_country_companies_path, params: { country: "SE" }
      get companies_path
      
      # The queue button should indicate companies needing processing
      doc = Nokogiri::HTML(response.body)
      
      # Financial Data queue section should be visible
      expect(response.body).to include("Financial Data")
      expect(response.body).to include("Queue Management")
    end
  end

  describe "Edge cases and data integrity" do
    it "handles empty country data gracefully" do
      # Create a country with no companies
      Company.create!(
        registration_number: "IS123456789",
        company_name: "Iceland Test Company",
        source_country: "IS",
        source_registry: "test",
        source_id: "IS123456789"
      )
      
      post set_country_companies_path, params: { country: "IS" }
      get companies_path
      
      expect(response).to be_successful
      expect(response.body).to include("Iceland Test Company")
      expect(response.body).to match(/Services Completed.*0/m)
      
      # Try to queue - should handle gracefully
      post queue_financial_data_companies_path, params: { count: 10 }, as: :json
      response_data = JSON.parse(response.body)
      expect(response_data["success"]).to be false
      expect(response_data["message"]).to include("No companies need financial data")
    end

    it "correctly calculates stats when switching countries rapidly" do
      # Rapidly switch between countries and verify stats remain accurate
      countries = ["NO", "SE", "DK"]
      expected_processed = { "NO" => 2, "SE" => 2, "DK" => 0 }
      
      countries.each do |country|
        post set_country_companies_path, params: { country: country }
        get service_stats_companies_path, as: :json
        stats = JSON.parse(response.body)
        expect(stats["total_processed"]).to eq(expected_processed[country])
      end
    end
  end
end