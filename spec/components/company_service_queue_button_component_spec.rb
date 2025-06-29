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
    # Mock Sidekiq queue
    allow(Sidekiq::Queue).to receive(:new).with(queue_name).and_return(
      double(size: 5)
    )
  end

  describe "regular service" do
    before do
      allow(Company).to receive(:needing_service).with(service_name).and_return(
        double(count: 10)
      )
      allow(Company).to receive(:needs_financial_update).and_return(
        double(count: 15)
      )
    end

    it "renders the component with correct counts" do
      render_inline(component)

      expect(page).to have_text(title)
      expect(page).to have_text("Financial Data Completion")
      expect(page).to have_text("0%")
      expect(page).to have_text("0 of 15 companies processed")
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
      allow(Company).to receive(:needing_service).with(service_name).and_return(
        double(count: 8)
      )
      allow(Company).to receive(:web_discovery_potential).and_return(
        double(count: 20)
      )
    end

    it "renders special text for web discovery" do
      render_inline(component)

      expect(page).to have_text("Web Discovery Completion")
      expect(page).to have_text("0%")
      expect(page).to have_text("0 of 20 companies processed")
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
      render_inline(component)

      expect(page).to have_text("Financial Data Completion")
      expect(page).to have_text("0%")
      expect(page).to have_text("0 of 0 companies processed")
      expect(page).to have_css("input[type='number'][min='1'][max='0']")
      expect(page).to have_css("input[type='number'][value='0']")
    end
  end
end
