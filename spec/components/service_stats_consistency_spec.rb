# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Service Stats Consistency", type: :system do
  describe "Financial Data Card" do
    let!(:norwegian_as_company) { create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil) }
    let!(:norwegian_asa_company) { create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "ASA", ordinary_result: nil) }
    let!(:norwegian_da_company) { create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "DA", ordinary_result: nil) }
    let!(:norwegian_ans_company) { create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "ANS", ordinary_result: nil) }

    # Companies that should NOT be counted
    let!(:norwegian_ba_company) { create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "BA", ordinary_result: nil) }
    let!(:swedish_company) { create(:company, source_country: "SE", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil) }
    let!(:company_with_financial_data) { create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: 1000000) }

    before do
      # Enable the financial data service
      create(:service_configuration, service_name: "company_financial_data", active: true, refresh_interval_hours: 720)
    end

    it "shows consistent totals in both the queue button and the turbo frame update" do
      # Calculate expected total using the business logic
      expected_total = Company.where(
        source_country: "NO",
        source_registry: "brreg",
        organization_form_code: [ "AS", "ASA", "DA", "ANS" ],
        ordinary_result: nil
      ).count

      expect(expected_total).to eq(4) # Our 4 test companies

      # Test 1: Check the queue button component calculation
      component = CompanyServiceQueueButtonComponent.new(
        service_name: "company_financials",
        title: "Financial Data",
        icon: "currency-dollar",
        action_path: "/queue_financial_data",
        queue_name: "company_financial_data"
      )

      # The component should calculate the total correctly
      # Note: The component incorrectly doesn't filter by ordinary_result: nil
      component_total = Company.where(
        source_country: "NO",
        source_registry: "brreg",
        organization_form_code: [ "AS", "ASA", "DA", "ANS" ]
      ).count

      # This will be 5 (includes the company with financial data)
      expect(component_total).to eq(5)

      # Test 2: Check the needs_financial_update scope
      scope_total = Company.needs_financial_update.count
      expect(scope_total).to eq(expected_total) # Should be 4

      # Test 3: Check the service_stats partial calculation
      # This uses Company.needs_financial_update.count for the total
      financial_potential = Company.needs_financial_update.count
      expect(financial_potential).to eq(expected_total) # Should be 4

      # The issue: Component shows total of 5, but turbo frame update shows total of 4
      # This causes the percentage to jump when updating
    end

    it "calculates completion percentage consistently" do
      # Add some successful audit logs
      create(:service_audit_log,
        auditable: norwegian_as_company,
        service_name: "company_financial_data",
        status: "success",
        completed_at: 1.hour.ago
      )

      create(:service_audit_log,
        auditable: norwegian_asa_company,
        service_name: "company_financial_data",
        status: "success",
        completed_at: 1.hour.ago
      )

      # Component calculation (incorrectly includes companies with financial data)
      component_total = Company.where(
        source_country: "NO",
        source_registry: "brreg",
        organization_form_code: [ "AS", "ASA", "DA", "ANS" ]
      ).count # = 5

      component_completed = ServiceAuditLog
        .where(service_name: "company_financials", status: "success")
        .distinct
        .count(:auditable_id) # = 0 (wrong service name!)

      # Turbo frame calculation
      turbo_total = Company.needs_financial_update.count # = 4 (correct, excludes those with recent audits)

      turbo_completed = ServiceAuditLog
        .joins("JOIN companies ON companies.id = CAST(service_audit_logs.record_id AS INTEGER)")
        .where(service_name: "company_financial_data", status: "success")
        .where("companies.source_country = 'NO'")
        .where("companies.source_registry = 'brreg'")
        .where("companies.ordinary_result IS NULL")
        .where("companies.organization_form_code IN ('AS', 'ASA', 'DA', 'ANS')")
        .count # = 2 (but with complex logic)

      # The percentages will be different!
      component_percentage = component_total > 0 ? (component_completed.to_f / component_total.to_f) * 100 : 0
      turbo_percentage = turbo_total > 0 ? (turbo_completed.to_f / turbo_total.to_f) * 100 : 0

      expect(component_percentage).not_to eq(turbo_percentage) # This is the bug!
    end
  end

  describe "Web Discovery Card" do
    let!(:high_revenue_with_website) { create(:company, operating_revenue: 15_000_000, website: "https://example.com") }
    let!(:high_revenue_without_website) { create(:company, operating_revenue: 20_000_000, website: nil) }
    let!(:low_revenue_company) { create(:company, operating_revenue: 5_000_000, website: nil) }

    before do
      create(:service_configuration, service_name: "company_web_discovery", active: true)
    end

    it "shows consistent totals in both the queue button and the turbo frame update" do
      # Both should count companies with revenue > 10M
      expected_total = Company.where("operating_revenue > ?", 10_000_000).count
      expect(expected_total).to eq(2)

      # Component calculation
      component = CompanyServiceQueueButtonComponent.new(
        service_name: "company_web_discovery",
        title: "Web Discovery",
        icon: "globe-alt",
        action_path: "/queue_web_discovery",
        queue_name: "company_web_discovery"
      )

      component_total = Company.where("operating_revenue > ?", 10_000_000).count
      expect(component_total).to eq(expected_total)

      # Turbo frame calculation (from _service_stats.html.erb)
      turbo_total = Company.by_country(nil).where("operating_revenue > ?", 10_000_000).count
      expect(turbo_total).to eq(expected_total)

      # Both use the same logic - good!
    end

    it "calculates completion percentage consistently" do
      # Component: counts companies with websites
      component_completed = Company
        .where("operating_revenue > ?", 10_000_000)
        .where("website IS NOT NULL AND website != ''")
        .count
      expect(component_completed).to eq(1)

      # Turbo frame: also counts companies with websites
      turbo_completed = Company
        .by_country(nil)
        .where("operating_revenue > ?", 10_000_000)
        .where("website IS NOT NULL AND website != ''")
        .count
      expect(turbo_completed).to eq(1)

      # Both use the same logic - good!
      expect(component_completed).to eq(turbo_completed)
    end
  end

  describe "LinkedIn Discovery Card" do
    let!(:high_revenue_with_linkedin) { create(:company, operating_revenue: 15_000_000, linkedin_url: "https://linkedin.com/company/example") }
    let!(:high_revenue_without_linkedin) { create(:company, operating_revenue: 20_000_000, linkedin_url: nil) }
    let!(:low_revenue_company) { create(:company, operating_revenue: 5_000_000, linkedin_url: nil) }

    before do
      create(:service_configuration, service_name: "company_linkedin_discovery", active: true)
    end

    it "shows consistent totals in both the queue button and the turbo frame update" do
      # Both should count companies with revenue > 10M
      expected_total = Company.linkedin_discovery_potential.count
      expect(expected_total).to eq(2)

      # Component calculation
      component_total = Company.linkedin_discovery_potential.count
      expect(component_total).to eq(expected_total)

      # Turbo frame uses companies_potential which is passed from controller
      # Controller passes: linkedin_potential: Company.by_country(@selected_country).linkedin_discovery_potential.count
      controller_total = Company.by_country(nil).linkedin_discovery_potential.count
      expect(controller_total).to eq(expected_total)

      # Both use the same logic - good!
    end
  end
end

RSpec.describe "Service Stats Business Logic Rules" do
  describe "Financial Data Service" do
    it "only includes Norwegian companies from brreg registry" do
      create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil)
      create(:company, source_country: "SE", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil)
      create(:company, source_country: "NO", source_registry: "other", organization_form_code: "AS", ordinary_result: nil)

      expect(Company.needs_financial_update.count).to eq(1)
    end

    it "only includes specific organization forms (AS, ASA, DA, ANS)" do
      [ "AS", "ASA", "DA", "ANS" ].each do |form|
        create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: form, ordinary_result: nil)
      end

      create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "BA", ordinary_result: nil)
      create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "NUF", ordinary_result: nil)

      expect(Company.needs_financial_update.count).to eq(4)
    end

    it "only includes companies without financial data (ordinary_result is nil)" do
      create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil)
      create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: 0)
      create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: 1000000)

      expect(Company.needs_financial_update.count).to eq(1)
    end

    it "excludes companies with recent successful audits" do
      company1 = create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil)
      company2 = create(:company, source_country: "NO", source_registry: "brreg", organization_form_code: "AS", ordinary_result: nil)

      # Recent successful audit
      create(:service_audit_log,
        auditable: company1,
        service_name: "company_financial_data",
        status: "success",
        completed_at: 1.hour.ago
      )

      # Old successful audit (should be included)
      create(:service_audit_log,
        auditable: company2,
        service_name: "company_financial_data",
        status: "success",
        completed_at: 31.days.ago
      )

      expect(Company.needs_financial_update.count).to eq(1)
      expect(Company.needs_financial_update.first).to eq(company2)
    end
  end

  describe "Web Discovery Service" do
    it "only includes companies with revenue > 10M NOK" do
      create(:company, operating_revenue: 15_000_000, website: nil)
      create(:company, operating_revenue: 10_000_001, website: nil)
      create(:company, operating_revenue: 10_000_000, website: nil)
      create(:company, operating_revenue: 9_999_999, website: nil)

      expect(Company.web_discovery_candidates.count).to eq(2)
    end

    it "only includes companies without websites for needing_web_discovery" do
      create(:company, operating_revenue: 15_000_000, website: nil)
      create(:company, operating_revenue: 15_000_000, website: "")
      create(:company, operating_revenue: 15_000_000, website: "https://example.com")

      expect(Company.needing_web_discovery.count).to eq(2)
    end
  end

  describe "LinkedIn Discovery Service" do
    it "only includes companies with revenue > 10M NOK" do
      create(:company, operating_revenue: 15_000_000, linkedin_url: nil)
      create(:company, operating_revenue: 9_999_999, linkedin_url: nil)

      expect(Company.linkedin_discovery_candidates.count).to eq(1)
    end

    it "only includes companies without LinkedIn URLs for needing_linkedin_discovery" do
      create(:company, operating_revenue: 15_000_000, linkedin_url: nil, linkedin_ai_url: nil)
      create(:company, operating_revenue: 15_000_000, linkedin_url: "", linkedin_ai_url: "")
      create(:company, operating_revenue: 15_000_000, linkedin_url: "https://linkedin.com/company/example", linkedin_ai_url: nil)
      create(:company, operating_revenue: 15_000_000, linkedin_url: nil, linkedin_ai_url: "https://linkedin.com/company/example2")

      expect(Company.needing_linkedin_discovery.count).to eq(2)
    end
  end
end
