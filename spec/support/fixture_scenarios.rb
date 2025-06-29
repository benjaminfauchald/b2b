# Fixture scenarios for common test cases
module FixtureScenarios
  # Load fixtures for web discovery testing
  def load_web_discovery_scenario
    # Companies needing web discovery
    @companies_needing_discovery = [
      companies(:norwegian_company_no_website),
      companies(:swedish_company_high_revenue)
    ].select { |c| c.operating_revenue > 10_000_000 && c.website.blank? }

    # Companies with successful web discovery
    @companies_with_websites = [
      companies(:norwegian_company_complete)
    ]
  end

  # Load fixtures for financial data testing
  def load_financial_data_scenario
    @companies_needing_financials = [
      companies(:norwegian_company_no_financials)
    ]

    @companies_with_financials = [
      companies(:norwegian_company_complete),
      companies(:swedish_company_high_revenue)
    ].select { |c| c.ordinary_result.present? }
  end

  # Load fixtures for country filtering
  def load_country_filtering_scenario
    @norwegian_companies = Company.where(source_country: "NO")
    @swedish_companies = Company.where(source_country: "SE")
    @all_countries = Company.distinct.pluck(:source_country).compact.sort
  end

  # Load fixtures for service audit testing
  def load_service_audit_scenario
    @successful_audits = [
      service_audit_logs(:successful_financial_audit),
      service_audit_logs(:successful_linkedin_discovery)
    ]

    @failed_audits = [
      service_audit_logs(:failed_web_discovery)
    ]
  end
end

# Include in RSpec
RSpec.configure do |config|
  config.include FixtureScenarios
end
