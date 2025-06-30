require 'rails_helper'

RSpec.describe "Country Filtering", type: :request do
  let(:user) { create(:user) }

  before do
    # Stub authentication
    allow_any_instance_of(ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)

    # Create test data - companies that meet financial data criteria
    create_list(:company, 5,
      source_country: "NO",
      company_name: "Norwegian Company",
      source_registry: "brreg",
      ordinary_result: nil,
      organization_form_code: "AS"
    )
    create_list(:company, 3,
      source_country: "SE",
      company_name: "Swedish Company",
      source_registry: "brreg",
      ordinary_result: nil,
      organization_form_code: "AS"
    )
    create_list(:company, 2,
      source_country: "DK",
      company_name: "Danish Company",
      source_registry: "brreg",
      ordinary_result: nil,
      organization_form_code: "AS"
    )

    # Create service audit logs for different countries
    Company.where(source_country: "NO").limit(2).each do |company|
      create(:service_audit_log,
        auditable: company,
        service_name: "company_financials",
        status: ServiceAuditLog::STATUS_SUCCESS
      )
    end

    Company.where(source_country: "SE").limit(1).each do |company|
      create(:service_audit_log,
        auditable: company,
        service_name: "company_web_discovery",
        status: ServiceAuditLog::STATUS_SUCCESS
      )
    end
  end

  describe "Country selection persistence" do
    it "maintains country selection across requests" do
      # Initial request - should default to first country
      get companies_path
      expect(response.body).to include("Danish Company")
      expect(response.body).not_to include("Norwegian Company")

      # Change country
      post set_country_companies_path, params: { country: "NO" }
      expect(response).to redirect_to(companies_path)

      # Follow redirect
      follow_redirect!
      expect(response.body).to include("Norwegian Company")
      expect(response.body).not_to include("Danish Company")

      # Subsequent request should remember selection
      get companies_path
      expect(response.body).to include("Norwegian Company")
      expect(response.body).not_to include("Danish Company")
    end
  end

  describe "Stats filtering by country" do
    it "shows country-specific statistics" do
      post set_country_companies_path, params: { country: "NO" }
      get companies_path

      # Check that stats reflect Norwegian data
      expect(response.body).to match(/Services Completed.*2/m) # 2 Norwegian services

      # Switch to Sweden
      post set_country_companies_path, params: { country: "SE" }
      follow_redirect!

      # Check that stats reflect Swedish data
      expect(response.body).to match(/Services Completed.*1/m) # 1 Swedish service
    end
  end

  describe "Queue operations" do
    before do
      # Create service configuration
      create(:service_configuration, service_name: "company_financial_data", active: true)
      allow(ServiceConfiguration).to receive(:active?).with("company_financial_data").and_return(true)
      post set_country_companies_path, params: { country: "NO" }
    end

    it "only affects companies from selected country" do
      # Mock worker to not actually process
      allow(CompanyFinancialDataWorker).to receive(:perform_async)

      post queue_financial_data_companies_path, params: { count: 5 }, as: :json

      response_data = JSON.parse(response.body)
      expect(response_data["success"]).to be true
      expect(response_data["queued_count"]).to eq(5) # Only Norwegian companies
    end
  end

  describe "Search within country" do
    it "searches only within selected country" do
      post set_country_companies_path, params: { country: "NO" }

      get companies_path, params: { search: "Company" }

      expect(response.body.scan(/Norwegian Company/).count).to eq(5)
      expect(response.body).not_to include("Swedish Company")
      expect(response.body).not_to include("Danish Company")
    end
  end

  describe "Country selector display" do
    it "shows country selector with all available countries" do
      get companies_path

      expect(response.body).to include("🇳🇴 Norway")
      expect(response.body).to include("🇸🇪 Sweden")
      expect(response.body).to include("🇩🇰 Denmark")
    end
  end
end
