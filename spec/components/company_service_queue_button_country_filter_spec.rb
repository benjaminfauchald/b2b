require "rails_helper"

RSpec.describe "CompanyServiceQueueButton with Country Filtering", type: :request do
  include Devise::Test::IntegrationHelpers
  
  let(:user) { create(:user) }
  
  before do
    # Sign in the user
    sign_in user
    
    # Enable financial service
    allow(ServiceConfiguration).to receive(:active?).with("company_financial_data").and_return(true)
    
    # Create companies for different countries with different financial states
    # Norwegian companies
    create_list(:company, 5, 
      source_country: "NO",
      source_registry: "brreg",
      organization_form_code: "AS",
      ordinary_result: nil,
      annual_result: nil
    )
    create_list(:company, 3, 
      source_country: "NO",
      ordinary_result: 1000000,
      annual_result: 1200000
    )
    
    # Swedish companies
    create_list(:company, 8, 
      source_country: "SE",
      source_registry: "brreg",
      organization_form_code: "AS",
      ordinary_result: nil,
      annual_result: nil
    )
    create_list(:company, 2, 
      source_country: "SE",
      ordinary_result: 2000000,
      annual_result: 2500000
    )
    
    # Danish companies
    create_list(:company, 2, 
      source_country: "DK",
      source_registry: "brreg",
      organization_form_code: "AS",
      ordinary_result: nil,
      annual_result: nil
    )
    create_list(:company, 4, 
      source_country: "DK",
      ordinary_result: 500000,
      annual_result: 600000
    )
  end

  describe "Financial Data queue button" do
    context "when Sweden is selected" do
      before do
        post set_country_companies_path, params: { country: "SE" }
      end

      it "shows queue button with count for Swedish companies only" do
        get companies_path
        
        # The financial queue button should show 8 Swedish companies needing updates
        expect(response.body).to include("Financial Data")
        
        # Check the data attributes that would be used by the queue button
        doc = Nokogiri::HTML(response.body)
        queue_button = doc.css('[data-service-name="company_financials"]').first
        
        # When we queue financial data, it should only affect Swedish companies
        post queue_financial_data_companies_path, params: { count: 5 }, as: :json
        response_data = JSON.parse(response.body)
        
        expect(response_data["available_count"]).to eq(8) # Only Swedish companies needing updates
      end

      it "processes only Swedish companies when queue button is clicked" do
        allow(CompanyFinancialsWorker).to receive(:perform_async)
        
        post queue_financial_data_companies_path, params: { count: 10 }, as: :json
        response_data = JSON.parse(response.body)
        
        expect(response_data["success"]).to be true
        expect(response_data["queued_count"]).to eq(8) # Can't queue more than available
        expect(response_data["message"]).to include("8 companies queued")
        
        # Verify the worker was called 8 times (for Swedish companies only)
        expect(CompanyFinancialsWorker).to have_received(:perform_async).exactly(8).times
      end
    end

    context "when Norway is selected" do
      before do
        post set_country_companies_path, params: { country: "NO" }
      end

      it "shows queue stats for Norwegian companies only" do
        get companies_path
        
        # Queue financial data for Norwegian companies
        post queue_financial_data_companies_path, params: { count: 10 }, as: :json
        response_data = JSON.parse(response.body)
        
        expect(response_data["available_count"]).to eq(5) # Only Norwegian companies needing updates
        expect(response_data["queued_count"]).to eq(5)
      end
    end

    context "when Denmark is selected" do
      before do
        post set_country_companies_path, params: { country: "DK" }
      end

      it "shows queue stats for Danish companies only" do
        get companies_path
        
        # Queue financial data for Danish companies
        post queue_financial_data_companies_path, params: { count: 10 }, as: :json
        response_data = JSON.parse(response.body)
        
        expect(response_data["available_count"]).to eq(2) # Only Danish companies needing updates
        expect(response_data["queued_count"]).to eq(2)
      end
    end
  end

  describe "Queue status updates respect country filter" do
    it "updates queue counts based on selected country" do
      # Select Sweden
      post set_country_companies_path, params: { country: "SE" }
      
      # Initial state - 8 Swedish companies need updates
      get enhancement_queue_status_companies_path, as: :json
      initial_status = JSON.parse(response.body)
      expect(initial_status["available_count"]).to eq(8)
      
      # Queue 5 companies
      allow(CompanyFinancialsWorker).to receive(:perform_async)
      post queue_financial_data_companies_path, params: { count: 5 }, as: :json
      
      # Mark some as processed by creating audit logs
      Company.where(source_country: "SE", ordinary_result: nil).limit(3).each do |company|
        create(:service_audit_log,
          auditable: company,
          service_name: "company_financial_data",
          status: ServiceAuditLog::STATUS_SUCCESS,
          completed_at: 1.minute.ago
        )
      end
      
      # Check updated status - should now show 5 available (8 - 3 processed)
      get enhancement_queue_status_companies_path, as: :json
      updated_status = JSON.parse(response.body)
      expect(updated_status["available_count"]).to eq(5)
    end
  end

  describe "Service stats endpoint with country filter" do
    before do
      # Create audit logs for different countries
      Company.where(source_country: "SE").limit(3).each do |company|
        create(:service_audit_log,
          auditable: company,
          service_name: "company_financials",
          status: ServiceAuditLog::STATUS_SUCCESS
        )
      end
      
      Company.where(source_country: "NO").limit(2).each do |company|
        create(:service_audit_log,
          auditable: company,
          service_name: "company_financials",
          status: ServiceAuditLog::STATUS_SUCCESS
        )
      end
    end

    it "returns country-specific financial service stats" do
      # Select Sweden
      post set_country_companies_path, params: { country: "SE" }
      get service_stats_companies_path, as: :json
      
      stats = JSON.parse(response.body)
      expect(stats["total_processed"]).to eq(3) # Only Swedish processed
      expect(stats["company_financial_data"]).to be_present
      
      # Switch to Norway
      post set_country_companies_path, params: { country: "NO" }
      get service_stats_companies_path, as: :json
      
      stats = JSON.parse(response.body)
      expect(stats["total_processed"]).to eq(2) # Only Norwegian processed
    end
  end
end