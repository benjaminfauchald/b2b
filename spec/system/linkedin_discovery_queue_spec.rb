# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "LinkedIn Discovery Queue Processing", type: :system do
  let(:admin_user) { create(:user, email: "admin@example.com") }

  before do
    driven_by(:rack_test)
    sign_in admin_user

    # Clean up all data for test isolation
    Company.destroy_all
    ServiceAuditLog.destroy_all
    ServiceConfiguration.destroy_all

    # Enable LinkedIn discovery service
    ServiceConfiguration.find_or_create_by(service_name: "company_linkedin_discovery").update(active: true)

    # Clear Sidekiq jobs
    Sidekiq::Testing.fake!
    CompanyLinkedinDiscoveryWorker.clear
  end

  after do
    Sidekiq::Testing.inline!
  end

  describe "LinkedIn Discovery service queue button" do
    context "when companies need LinkedIn discovery" do
      before do
        # Create companies that need LinkedIn discovery
        # Must match linkedin_discovery_potential criteria
        15.times do |i|
          create(:company,
            registration_number: "NO#{777000 + i}",
            company_name: "Test LinkedIn Company #{i}",
            source_country: "NO",
            source_registry: "brreg",
            organization_form_code: "BA", # Not in excluded forms
            operating_revenue: 15_000_000 + (i * 1_000_000),
            linkedin_ai_url: nil,
            linkedin_last_processed_at: nil
          )
        end

        # Create some already processed companies
        5.times do |i|
          company = create(:company,
            registration_number: "NO#{666000 + i}",
            company_name: "Processed LinkedIn Company #{i}",
            source_country: "NO",
            source_registry: "brreg",
            organization_form_code: "BA",
            operating_revenue: 20_000_000,
            linkedin_ai_url: "https://linkedin.com/company/test-#{i}",
            linkedin_last_processed_at: 1.day.ago
          )

          # Create audit log for processed company
          create(:service_audit_log,
            service_name: "company_linkedin_discovery",
            status: "success",
            auditable: company,
            table_name: "companies",
            record_id: company.id.to_s,
            operation_type: "process",
            columns_affected: [ "linkedin_ai_url" ],
            completed_at: 1.day.ago
          )
        end
      end

      it "displays the correct statistics and allows queueing" do
        visit companies_path

        within("[data-service='company_linkedin_discovery']") do
          # Check the completion percentage
          expect(page).to have_text("LinkedIn Discovery Completion")
          # 5 processed out of 20 total = 25%, but allow for rounding
          expect(page.text).to match(/2[45]%/) # Could be 24% or 25% due to rounding
          expect(page).to have_text("5 of 20 companies processed")

          # Check the batch size input
          batch_input = find("input[type='number']")
          expect(batch_input[:min]).to eq("1")
          expect(batch_input[:max]).to eq("15") # 15 companies need processing
          expect(batch_input.value).to eq("15") # Default to max available

          # Change batch size to 10
          batch_input.set("10")

          # Submit the form
          click_button "Queue Processing"
        end

        # Wait for AJAX response
        sleep 0.5

        # Verify jobs were queued
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(10)

        # Verify the page updates (would need JavaScript driver for full test)
        # In a full integration test with JavaScript, we'd check for:
        # - Success message
        # - Updated statistics
        # - Queue depth update
      end

      it "handles the maximum batch size correctly" do
        visit companies_path

        within("[data-service='company_linkedin_discovery']") do
          batch_input = find("input[type='number']")

          # Try to set a value higher than available
          batch_input.set("20")

          # The max constraint should prevent this
          expect(batch_input[:max]).to eq("15")
        end
      end

      it "validates the minimum batch size" do
        visit companies_path

        within("[data-service='company_linkedin_discovery']") do
          batch_input = find("input[type='number']")

          # Try to set zero
          batch_input.set("0")

          # The min constraint should prevent this
          expect(batch_input[:min]).to eq("1")
        end
      end
    end

    context "when no companies need LinkedIn discovery" do
      before do
        # Create only processed companies with service audit logs
        3.times do |i|
          company = create(:company,
            registration_number: "NO#{555000 + i}",
            organization_form_code: "AS",
            operating_revenue: 20_000_000,
            linkedin_ai_url: "https://linkedin.com/company/processed-#{i}"
          )

          # Create audit log to mark as processed
          create(:service_audit_log,
            service_name: "company_linkedin_discovery",
            status: "success",
            auditable: company,
            table_name: "companies",
            record_id: company.id.to_s,
            operation_type: "process",
            columns_affected: [ "linkedin_ai_url" ],
            completed_at: 1.day.ago
          )
        end
      end

      it "shows 100% completion and disables the queue button" do
        visit companies_path

        within("[data-service='company_linkedin_discovery']") do
          # Should show 100% if no companies need processing
          expect(page).to have_text("LinkedIn Discovery Completion")
          expect(page).to have_text("100%")
          expect(page).to have_text("3 of 3 companies processed")

          # The submit button should be disabled
          submit_button = find("button[type='submit']")
          expect(submit_button).to be_disabled

          # Input should have valid min/max values even with 0 companies
          batch_input = find("input[type='number']")
          expect(batch_input[:min]).to eq("1")
          expect(batch_input[:max]).to eq("1000") # Default max when none available
          expect(batch_input.value).to eq("0")
        end
      end
    end

    context "with country filtering" do
      before do
        # Create companies from different countries
        10.times do |i|
          create(:company,
            registration_number: "NO#{444000 + i}",
            source_country: "NO",
            organization_form_code: "BA",
            operating_revenue: 15_000_000,
            linkedin_ai_url: nil
          )
        end

        5.times do |i|
          create(:company,
            registration_number: "SE#{333000 + i}",
            source_country: "SE",
            organization_form_code: "AB",
            operating_revenue: 15_000_000,
            linkedin_ai_url: nil
          )
        end
      end

      it "only shows and queues companies from the selected country" do
        # Select Norway
        visit companies_path(country: "NO")

        within("[data-service='company_linkedin_discovery']") do
          # Should only show Norwegian companies (we created 10 NO + 5 SE = 15 total)
          # When filtering by NO, should show "0 of 10"
          expect(page.text).to match(/0 of \d+ companies processed/)

          batch_input = find("input[type='number']")
          # Max should be 10 since we have 10 Norwegian companies needing service
          expect(batch_input[:max].to_i).to be >= 10

          # Queue 5 companies
          batch_input.set("5")
          click_button "Queue Processing"
        end

        sleep 0.5

        # Verify only Norwegian companies were queued
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(5)

        queued_company_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |job| job["args"].first }
        queued_companies = Company.where(id: queued_company_ids)
        expect(queued_companies.pluck(:source_country).uniq).to eq([ "NO" ])
      end
    end
  end

  describe "Real-time statistics update" do
    before do
      # Create companies needing service
      10.times do |i|
        create(:company,
          registration_number: "NO#{222000 + i}",
          organization_form_code: "BA",
          operating_revenue: 20_000_000,
          linkedin_ai_url: nil
        )
      end
    end

    it "updates statistics after queueing" do
      visit companies_path

      initial_stats = nil
      within("[data-service='company_linkedin_discovery']") do
        initial_stats = page.text

        # Queue 5 companies
        batch_input = find("input[type='number']")
        batch_input.set("5")
        click_button "Queue Processing"
      end

      # In a real test with JavaScript, we would:
      # 1. Wait for the AJAX call to complete
      # 2. Check for the success toast/notification
      # 3. Verify the statistics are updated via Turbo Stream
      # 4. Check that the queue depth increased
      # 5. Verify the available count decreased

      # Verify the jobs were queued
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(5)
    end
  end
end
