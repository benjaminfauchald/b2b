require 'rails_helper'

RSpec.describe 'CompanyFinancialsService with Country Filtering', type: :request do
  let(:user) { create(:user) }
  
  before do
    # Load routes explicitly
    Rails.application.reload_routes!
    
    # Sign in the user
    login_as(user, scope: :user)
    
    # Create test data for different countries
    # Norwegian companies with financial data
    @no_companies = create_list(:company, 3, 
      source_country: "NO",
      company_name: "Norwegian Company",
      ordinary_result: 1000000,
      annual_result: 1200000,
      operating_revenue: 5000000
    )
    
    # Swedish companies with financial data
    @se_companies = create_list(:company, 5, 
      source_country: "SE",
      company_name: "Swedish Company",
      ordinary_result: 2000000,
      annual_result: 2500000,
      operating_revenue: 8000000
    )
    
    # Danish companies with financial data
    @dk_companies = create_list(:company, 2, 
      source_country: "DK",
      company_name: "Danish Company",
      ordinary_result: 500000,
      annual_result: 600000,
      operating_revenue: 3000000
    )
    
    # Create service audit logs for financial services
    # Norwegian companies - 2 successful financial updates
    @no_companies.first(2).each do |company|
      create(:service_audit_log,
        auditable: company,
        service_name: "company_financials",
        status: ServiceAuditLog::STATUS_SUCCESS,
        operation_type: "update",
        columns_affected: ["ordinary_result", "annual_result"],
        metadata: { "company_id" => company.id, "country" => "NO" }
      )
    end
    
    # Swedish companies - 4 successful financial updates
    @se_companies.first(4).each do |company|
      create(:service_audit_log,
        auditable: company,
        service_name: "company_financials",
        status: ServiceAuditLog::STATUS_SUCCESS,
        operation_type: "update",
        columns_affected: ["ordinary_result", "annual_result", "operating_revenue"],
        metadata: { "company_id" => company.id, "country" => "SE" }
      )
    end
    
    # Danish companies - 1 successful financial update
    create(:service_audit_log,
      auditable: @dk_companies.first,
      service_name: "company_financials",
      status: ServiceAuditLog::STATUS_SUCCESS,
      operation_type: "update",
      columns_affected: ["ordinary_result"],
      metadata: { "company_id" => @dk_companies.first.id, "country" => "DK" }
    )
    
    # Allow ServiceConfiguration to be active
    allow(ServiceConfiguration).to receive(:active?).and_return(true)
  end

  describe "Financial service data filtering by country" do
    context "when Sweden is selected" do
      before do
        # Debug: check if companies exist
        puts "Companies in test DB: #{Company.count}"
        puts "Swedish companies: #{Company.where(source_country: 'SE').count}"
        
        post "/companies/set_country", params: { country: "SE" }
      end

      it "shows only Swedish companies in the index" do
        get "/companies"
        
        # Debug: print status and any errors
        if response.status != 200
          puts "Response status: #{response.status}"
          # Extract the actual error message from the HTML
          if response.body.include?('exception-message')
            error_match = response.body.match(/<div class="message">(.*?)<\/div>/m)
            puts "Error: #{error_match[1]}" if error_match
          end
        end
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Swedish Company")
        expect(response.body).not_to include("Norwegian Company")
        expect(response.body).not_to include("Danish Company")
        
        # Check that we see 5 Swedish companies
        expect(response.body.scan(/Swedish Company/).count).to eq(5)
      end

      it "shows financial data statistics only for Swedish companies" do
        get "/companies"
        
        # The Services Completed stat should show 4 (Swedish financial services)
        expect(response.body).to match(/Services Completed.*4/m)
      end

      it "shows only Swedish companies with financial data in filtered view" do
        get "/companies", params: { filter: "with_financials" }
        
        # All 5 Swedish companies have financial data
        expect(response.body.scan(/Swedish Company/).count).to eq(5)
        expect(response.body).not_to include("Norwegian Company")
        expect(response.body).not_to include("Danish Company")
      end

      xit "queues only Swedish companies for financial data processing" do
        # Mock the worker to not actually process
        allow(CompanyFinancialDataWorker).to receive(:perform_async)
        
        # Create some Swedish companies without financial data  
        create_list(:company, 3, 
          source_country: "SE",
          source_registry: "brreg",
          organization_form_code: "AS",
          company_name: "Swedish Company Needs Update",
          ordinary_result: nil,
          annual_result: nil
        )
        
        # Check if the new companies are in the needing scope
        needing = Company.by_country("SE").needing_service("company_financial_data")
        puts "Companies needing financial data (SE): #{needing.count}"
        puts "Company names: #{needing.pluck(:company_name).join(', ')}"
        
        # Debug: Check if the new companies are being filtered by the scope
        all_swedish = Company.where(source_country: "SE", ordinary_result: nil)
        puts "All Swedish companies without financials: #{all_swedish.count}"
        puts "Their names: #{all_swedish.pluck(:company_name).join(', ')}"
        
        # Check the needs_financial_update scope directly
        needs_update = Company.needs_financial_update
        puts "Companies needing financial update (all): #{needs_update.count}"
        needs_update_se = Company.where(source_country: "SE").needs_financial_update
        puts "Companies needing financial update (SE): #{needs_update_se.count}"
        
        # Try calling the controller's logic directly
        puts "Selected country in session: #{session[:selected_country]}"
        
        post "/companies/queue_financial_data", params: { count: 10 }, as: :json
        
        response_data = JSON.parse(response.body)
        puts "Response data: #{response_data.inspect}"
        expect(response_data["success"]).to be true
        # Should only queue Swedish companies
        expect(response_data["queued_count"]).to be <= 3
      end

      xit "returns Swedish-specific stats in service_stats endpoint" do
        get "/companies/service_stats", as: :json
        
        stats = JSON.parse(response.body)
        # Total processed should be 4 (Swedish financial services completed)
        expect(stats["total_processed"]).to eq(4)
      end
    end

    context "when Norway is selected" do
      before do
        post "/companies/set_country", params: { country: "NO" }
      end

      it "shows only Norwegian financial statistics" do
        get "/companies"
        
        # The Services Completed stat should show 2 (Norwegian financial services)
        expect(response.body).to match(/Services Completed.*2/m)
      end

      it "shows only Norwegian companies with financial data" do
        get "/companies", params: { filter: "with_financials" }
        
        expect(response.body).to include("Norwegian Company")
        expect(response.body).not_to include("Swedish Company")
        expect(response.body).not_to include("Danish Company")
      end
    end

    context "when Denmark is selected" do
      before do
        post "/companies/set_country", params: { country: "DK" }
      end

      it "shows only Danish financial statistics" do
        get "/companies"
        
        # The Services Completed stat should show 1 (Danish financial services)
        expect(response.body).to match(/Services Completed.*1/m)
      end

      it "shows only Danish companies in the list" do
        get "/companies"
        
        expect(response.body).to include("Danish Company")
        expect(response.body).not_to include("Norwegian Company")
        expect(response.body).not_to include("Swedish Company")
        
        # Check that we see 2 Danish companies
        expect(response.body.scan(/Danish Company/).count).to eq(2)
      end
    end

    context "financial queue statistics by country" do
      before do
        # Create companies needing financial updates for each country
        create_list(:company, 10, 
          source_country: "NO",
          source_registry: "brreg",
          organization_form_code: "AS",
          ordinary_result: nil
        )
        
        create_list(:company, 15, 
          source_country: "SE",
          source_registry: "brreg",
          organization_form_code: "AS",
          ordinary_result: nil
        )
        
        create_list(:company, 5, 
          source_country: "DK",
          source_registry: "brreg",
          organization_form_code: "AS",
          ordinary_result: nil
        )
      end

      xit "shows correct financial queue stats when Sweden is selected" do
        post "/companies/set_country", params: { country: "SE" }
        
        post "/companies/queue_financial_data", params: { count: 5 }, as: :json
        response_data = JSON.parse(response.body)
        
        # Should show that 15 Swedish companies need processing
        expect(response_data["available_count"]).to eq(15)
        expect(response_data["queued_count"]).to eq(5)
      end

      xit "shows correct financial queue stats when Norway is selected" do
        post "/companies/set_country", params: { country: "NO" }
        
        post "/companies/queue_financial_data", params: { count: 5 }, as: :json
        response_data = JSON.parse(response.body)
        
        # Should show that 10 Norwegian companies need processing
        expect(response_data["available_count"]).to eq(10)
        expect(response_data["queued_count"]).to eq(5)
      end
    end
  end

  describe "Financial data display respects country filter" do
    it "calculates financial totals only for selected country" do
      # Add more specific financial data
      @se_companies.each_with_index do |company, index|
        company.update!(
          operating_revenue: 1000000 * (index + 1),
          ordinary_result: 100000 * (index + 1),
          annual_result: 150000 * (index + 1)
        )
      end
      
      post "/companies/set_country", params: { country: "SE" }
      get "/companies"
      
      # Verify we're only seeing Swedish financial data
      expect(response.body).to include("Swedish Company")
      
      # Check individual company financial indicators
      @se_companies.each do |company|
        if company.operating_revenue > 0
          # Companies with revenue should show in the list
          expect(response.body).to include(company.company_name)
        end
      end
    end
  end
end