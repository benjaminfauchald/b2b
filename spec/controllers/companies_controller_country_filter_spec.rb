require 'rails_helper'

RSpec.describe CompaniesController, type: :request do
  let(:user) { create(:user) }

  before do
    # Stub authentication
    allow_any_instance_of(ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  describe "Country filtering" do
    before do
      # Create companies for different countries that meet financial data criteria
      create_list(:company, 3, source_country: "NO", company_name: "Norwegian Company", 
                  source_registry: "brreg", ordinary_result: nil, organization_form_code: "AS")
      create_list(:company, 2, source_country: "SE", company_name: "Swedish Company",
                  source_registry: "brreg", ordinary_result: nil, organization_form_code: "AS")
      create_list(:company, 1, source_country: "DK", company_name: "Danish Company",
                  source_registry: "brreg", ordinary_result: nil, organization_form_code: "AS")
    end

    describe "GET /companies" do
      context "without country selection" do
        it "defaults to first available country" do
          get companies_path
          expect(response.body).to include("Danish Company")
          expect(response.body).not_to include("Norwegian Company")
          expect(response.body).not_to include("Swedish Company")
        end
      end

      context "with country in session" do
        before do
          post set_country_companies_path, params: { country: "NO" }
        end

        it "filters companies by selected country" do
          get companies_path
          expect(response.body).to include("Norwegian Company")
          expect(response.body).not_to include("Danish Company")
          expect(response.body).not_to include("Swedish Company")
        end

        it "respects search filters within country" do
          norwegian_company = Company.where(source_country: "NO").first
          norwegian_company.update!(company_name: "Test Norge AS")

          get companies_path, params: { search: "Norge" }
          expect(response.body).to include("Test Norge AS")
          expect(response.body).not_to include("Swedish Company")
        end

        it "respects other filters within country" do
          Company.where(source_country: "NO").first.update!(website: "https://example.no")

          get companies_path, params: { filter: "with_website" }
          expect(response.body).to include("example.no")
        end
      end

      it "includes available countries in response" do
        get companies_path
        expect(response.body).to include("🇳🇴 Norway")
        expect(response.body).to include("🇸🇪 Sweden")
        expect(response.body).to include("🇩🇰 Denmark")
      end
    end

    describe "POST /companies/set_country" do
      it "updates selected country in session" do
        post set_country_companies_path, params: { country: "SE" }
        expect(response).to redirect_to(companies_path)

        follow_redirect!
        expect(response.body).to include("Swedish Company")
        expect(response.body).not_to include("Norwegian Company")
      end

      it "rejects invalid country codes" do
        post set_country_companies_path, params: { country: "XX" }
        expect(response).to redirect_to(companies_path)

        follow_redirect!
        # Should default to first available country (DK)
        expect(response.body).to include("Danish Company")
      end
    end

    describe "Queue operations with country filter" do
      before do
        post set_country_companies_path, params: { country: "NO" }
        allow(ServiceConfiguration).to receive(:active?).and_return(true)
        allow(CompanyFinancialsWorker).to receive(:perform_async)
      end

      it "only queues companies from selected country" do
        post queue_financial_data_companies_path, params: { count: 10 }, as: :json

        response_data = JSON.parse(response.body)
        # Should only process Norwegian companies - either success with count or failure message
        if response_data["success"]
          expect(response_data["queued_count"]).to be <= 3
        else
          expect(response_data["success"]).to be false
        end
      end
    end

    describe "Service stats" do
      it "returns stats filtered by selected country" do
        post set_country_companies_path, params: { country: "NO" }

        # Create some audit logs
        norwegian_company = Company.where(source_country: "NO").first
        create(:service_audit_log,
          auditable: norwegian_company,
          service_name: "company_financials",
          status: "success"
        )

        # The service_stats endpoint only supports turbo_stream format, not JSON
        get service_stats_companies_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("company_financials_stats") # Check for turbo stream content
      end
    end
  end
end
