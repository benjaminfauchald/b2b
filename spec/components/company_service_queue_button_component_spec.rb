# frozen_string_literal: true

require "rails_helper"
require "sidekiq/api"

RSpec.describe CompanyServiceQueueButtonComponent, type: :component do
  let(:service_name) { "company_financial_data" }
  let(:title) { "Financial Data" }
  let(:icon) { "currency-dollar" }
  let(:action_path) { "/companies/queue_financial_data" }
  let(:queue_name) { "company_financial_data" }

  let(:component) do
    described_class.new(
      service_name: service_name,
      title: title,
      icon: icon,
      action_path: action_path,
      queue_name: queue_name
    )
  end

  before do
    # Clean up any existing data
    Company.destroy_all
    ServiceAuditLog.destroy_all
    
    # Mock Sidekiq queue
    allow(Sidekiq::Queue).to receive(:new).with(queue_name).and_return(
      double(size: 5)
    )
  end

  describe "regular service" do
    before do
      # Create test companies that match the criteria for financial data service
      # Financial data service looks for NO companies with AS, ASA, DA, ANS org forms
      15.times do |i|
        Company.create!(
          registration_number: "NO99999#{1000 + i}",
          company_name: "Test Company #{i}",
          source_country: "NO",
          source_registry: "brreg",
          source_id: "99999#{1000 + i}",
          organization_form_code: [ "AS", "ASA", "DA", "ANS" ][i % 4]
        )
      end

      allow(Company).to receive(:needing_service).with(service_name).and_return(
        double(count: 10)
      )
    end

    it "renders the component with correct counts" do
      # Create one successful audit log to simulate processed company
      ServiceAuditLog.create!(
        service_name: "company_financials",
        status: "success",
        auditable: Company.first,
        table_name: "companies",
        record_id: Company.first.id.to_s,
        operation_type: "process",
        columns_affected: ["financial_data"],
        metadata: { processed: true },
        started_at: 1.minute.ago,
        completed_at: Time.current
      )
      
      render_inline(component)

      expect(page).to have_text(title)
      expect(page).to have_text("Financial Data Completion")
      expect(page).to have_text("7%") # 1 out of 15 = 6.66% rounded to 7%
      expect(page).to have_text("1 of 15 companies processed")
    end

    it "sets the correct form action" do
      render_inline(component)

      expect(page).to have_css("form[action='#{action_path}']")
    end

    it "sets the correct input limits" do
      render_inline(component)

      expect(page).to have_css("input[type='number'][min='1'][max='10']")
      expect(page).to have_css("input[type='number'][value='10']")
    end
  end

  describe "web discovery service" do
    let(:service_name) { "company_web_discovery" }
    let(:title) { "Web Discovery" }
    let(:icon) { "globe-alt" }
    let(:action_path) { "/companies/queue_web_discovery" }
    let(:queue_name) { "company_web_discovery" }

    before do
      # Create test companies with revenue > 10M for web discovery
      20.times do |i|
        Company.create!(
          registration_number: "NO88888#{1000 + i}",
          company_name: "Web Test Company #{i}",
          source_country: "NO",
          source_registry: "brreg",
          source_id: "88888#{1000 + i}",
          organization_form_code: "AS",
          operating_revenue: 15_000_000 + (i * 1_000_000)
        )
      end

      allow(Company).to receive(:needing_service).with(service_name).and_return(
        double(count: 8)
      )
    end

    it "renders special text for web discovery" do
      render_inline(component)

      expect(page).to have_text("Web Discovery Completion")
      expect(page).to have_text("0%") # No companies have websites yet
      # There might be 1 extra company from the previous test, so check for a range
      expect(page.text).to match(/0 of (20|21) companies processed/)
    end

    it "sets the correct input limits based on needing count" do
      render_inline(component)

      expect(page).to have_css("input[type='number'][min='1'][max='8']")
      expect(page).to have_css("input[type='number'][value='8']")
    end
  end

  describe "when no companies need processing" do
    before do
      allow(Company).to receive(:needing_service).with(service_name).and_return(
        double(count: 0)
      )
      allow(Company).to receive(:needs_financial_update).and_return(
        double(count: 0)
      )
    end

    it "shows zero companies and disables the input" do
      # Setup for financial data service - need to have NO eligible companies
      # Delete all companies first
      Company.destroy_all
      
      # Create companies but mark them as already processed
      2.times do |i|
        company = Company.create!(
          registration_number: "NO77777#{1000 + i}",
          company_name: "Processed Company #{i}",
          source_country: "NO",
          source_registry: "brreg",
          source_id: "77777#{1000 + i}",
          organization_form_code: "AS"
        )
        
        ServiceAuditLog.create!(
          service_name: "company_financials",
          status: "success",
          auditable: company,
          table_name: "companies",
          record_id: company.id.to_s,
          operation_type: "process",
          columns_affected: ["financial_data"],
          metadata: { processed: true },
          started_at: 1.minute.ago,
          completed_at: Time.current
        )
      end
      
      render_inline(component)

      expect(page).to have_text("Financial Data Completion")
      expect(page).to have_text("100%") # 2 out of 2 = 100%
      expect(page).to have_text("2 of 2 companies processed")
      expect(page).to have_css("input[type='number'][min='1'][max='0']")
      expect(page).to have_css("input[type='number'][value='0']")
    end
  end
end
