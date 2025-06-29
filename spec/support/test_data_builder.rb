# Builder pattern for complex test data scenarios
class TestDataBuilder
  def self.build_complete_company_scenario
    company = Company.create!(
      registration_number: "TEST#{SecureRandom.hex(4)}",
      company_name: "Test Company AS",
      source_country: "NO",
      source_registry: "brreg",
      organization_form_code: "AS",
      operating_revenue: 25_000_000,
      ordinary_result: 2_500_000,
      annual_result: 2_000_000,
      website: "https://testcompany.no",
      linkedin_url: "https://linkedin.com/company/testcompany"
    )
    
    # Add service audit logs
    ServiceAuditLog.create!(
      auditable: company,
      service_name: "company_financials",
      status: ServiceAuditLog::STATUS_SUCCESS,
      operation_type: "update",
      columns_affected: ["ordinary_result", "annual_result"],
      started_at: 1.hour.ago,
      completed_at: 50.minutes.ago
    )
    
    ServiceAuditLog.create!(
      auditable: company,
      service_name: "company_web_discovery",
      status: ServiceAuditLog::STATUS_SUCCESS,
      operation_type: "discover",
      metadata: { pages_found: 5, confidence_scores: [80, 75, 70, 65, 60] },
      started_at: 2.hours.ago,
      completed_at: 1.hour.ago
    )
    
    company
  end
  
  def self.build_web_discovery_test_set
    companies = []
    
    # Company with high revenue, no website
    companies << Company.create!(
      registration_number: "WD001",
      company_name: "High Revenue No Web AS",
      source_country: "NO",
      operating_revenue: 50_000_000,
      website: nil
    )
    
    # Company with low revenue, no website (should not be included)
    companies << Company.create!(
      registration_number: "WD002",
      company_name: "Low Revenue No Web AS",
      source_country: "NO",
      operating_revenue: 5_000_000,
      website: nil
    )
    
    # Company with high revenue and website
    companies << Company.create!(
      registration_number: "WD003",
      company_name: "High Revenue With Web AS",
      source_country: "NO",
      operating_revenue: 75_000_000,
      website: "https://example.no"
    )
    
    companies
  end
  
  def self.build_country_filtering_test_set
    countries = %w[NO SE DK FI]
    companies = []
    
    countries.each do |country|
      3.times do |i|
        companies << Company.create!(
          registration_number: "#{country}#{i + 1000}",
          company_name: "#{country} Company #{i + 1}",
          source_country: country,
          operating_revenue: (10_000_000 * (i + 1))
        )
      end
    end
    
    companies
  end
end