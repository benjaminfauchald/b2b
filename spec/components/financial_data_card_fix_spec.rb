# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Financial Data Card Consistency Fix" do
  describe "Issues to fix" do
    it "identifies the inconsistencies in financial data calculations" do
      # Issue 1: Service name mismatch
      # - Component uses "company_financials"
      # - Turbo frame uses "company_financial_data"
      # - ServiceAuditLog records use "company_financials"

      # Issue 2: Total calculation mismatch
      # - Component: counts ALL companies with NO/brreg/AS,ASA,DA,ANS
      # - Turbo frame: uses needs_financial_update scope which ALSO filters by ordinary_result: nil

      # Issue 3: Completed calculation mismatch
      # - Component: counts by service name "company_financials"
      # - Turbo frame: complex join with multiple conditions

      # Issue 4: The needs_financial_update scope excludes companies with recent successful audits
      # - This means the total shrinks as companies are processed!
      # - This causes the percentage to suddenly jump to 0% when all are processed
    end
  end

  describe "Proposed fixes" do
    it "outlines the changes needed for consistency" do
      # Fix 1: Standardize on ONE service name throughout
      # - Use "company_financial_data" everywhere (it's what the worker uses)

      # Fix 2: Use the SAME total calculation in both places
      # - Both should use the base criteria WITHOUT excluding recent audits
      # - Total should be: Company.where(source_country: "NO", source_registry: "brreg",
      #                                 organization_form_code: ["AS", "ASA", "DA", "ANS"],
      #                                 ordinary_result: nil).count

      # Fix 3: Use the SAME completed calculation in both places
      # - Count companies that have EVER been successfully processed
      # - OR count companies that currently have financial data (ordinary_result NOT nil)

      # Fix 4: Create a separate scope for "total eligible" vs "needs processing"
      # - financial_data_eligible: base criteria (for calculating percentage)
      # - needs_financial_update: eligible AND no recent audit (for queueing)
    end
  end
end
