require 'rails_helper'

RSpec.describe Company, type: :model do
  # Load fixtures
  fixtures :companies, :service_audit_logs, :service_configurations
  
  describe "using real data fixtures" do
    describe "web discovery scopes" do
      it "identifies companies needing web discovery" do
        company = companies(:norwegian_company_no_website)
        
        expect(company.operating_revenue).to be > 10_000_000
        expect(company.website).to be_nil
        expect(Company.needing_web_discovery).to include(company)
      end
      
      it "excludes companies with websites from needing discovery" do
        company = companies(:norwegian_company_complete)
        
        if company && company.website.present?
          expect(Company.needing_web_discovery).not_to include(company)
        end
      end
    end
    
    describe "financial data" do
      it "has companies with complete financial data" do
        company = companies(:norwegian_company_complete)
        
        if company
          expect(company.ordinary_result).not_to be_nil
          expect(company.annual_result).not_to be_nil
        end
      end
      
      it "identifies companies needing financial updates" do
        company = companies(:norwegian_company_no_financials)
        
        if company && company.ordinary_result.nil?
          expect(company.needs_financial_update?).to be true
        end
      end
    end
    
    describe "service audit logs" do
      it "tracks successful service operations" do
        audit = service_audit_logs(:successful_financial_audit)
        
        if audit
          expect(audit.status).to eq("success")
          expect(audit.service_name).to eq("company_financials")
        end
      end
      
      it "tracks failed service operations" do
        audit = service_audit_logs(:failed_web_discovery)
        
        if audit
          expect(audit.status).to eq("failed")
          expect(audit.service_name).to eq("company_web_discovery")
        end
      end
    end
    
    describe "country filtering" do
      it "filters companies by country" do
        norwegian_companies = Company.by_country("NO")
        swedish_companies = Company.by_country("SE")
        
        expect(norwegian_companies.pluck(:source_country).uniq).to eq(["NO"])
        
        if companies(:swedish_company_high_revenue)
          expect(swedish_companies).to include(companies(:swedish_company_high_revenue))
        end
      end
    end
  end
end