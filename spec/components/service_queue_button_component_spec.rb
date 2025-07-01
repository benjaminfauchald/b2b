# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceQueueButtonComponent, type: :component do
  let(:component) do
    described_class.new(
      service_name: "domain_testing",
      title: "DNS Testing",
      icon: "🌐",
      action_path: "/domains/queue_dns_testing",
      queue_name: "domain_dns_testing"
    )
  end

  before do
    # Mock Sidekiq queue
    allow(Sidekiq::Queue).to receive(:new).and_return(double(size: 0))
    # Mock Domain methods
    allow(Domain).to receive(:dns_active).and_return(double(count: 0))
    allow(Domain).to receive(:with_mx).and_return(double(count: 0))
    allow(Domain).to receive(:www_active).and_return(double(count: 0))
    allow(Domain).to receive(:with_web_content).and_return(double(count: 0))
    allow(Domain).to receive_message_chain(:needing_service, :count).and_return(0)
  end

  describe "basic rendering" do
    it "renders service title" do
      render_inline(component)

      expect(page).to have_css("h3", text: "DNS Testing")
    end

    it "renders with icon" do
      render_inline(component)

      expect(page).to have_text("🌐")
    end

    it "renders form with correct action path" do
      render_inline(component)

      expect(page).to have_css("form[action='/domains/queue_dns_testing']")
      expect(page).to have_css("form[method='post']")
    end

    it "renders count input field with default value" do
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(100)

      render_inline(component)

      expect(page).to have_field("count", with: "10")
      expect(page).to have_css("input[type='number'][min='1'][max='100']")
    end

    it "renders submit button with Flowbite styling" do
      # Mock domains needing service to enable the button
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(10)

      render_inline(component)

      expect(page).to have_button("Queue Testing")
      expect(page).to have_css("button.text-white.bg-blue-700.hover\\:bg-blue-800")
      expect(page).to have_css("button.focus\\:ring-4.focus\\:ring-blue-300")
      expect(page).to have_css("button.font-medium.rounded-lg")
    end
  end

  describe "domains needing service" do
    before do
      allow(Domain).to receive(:dns_active).and_return(double(count: 0))
      allow(Domain).to receive(:with_mx).and_return(double(count: 0))
      allow(Domain).to receive(:www_active).and_return(double(count: 0))
      allow(Domain).to receive(:with_web_content).and_return(double(count: 0))
    end

    it "shows count of domains needing service" do
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(42)

      render_inline(component)

      expect(page).to have_text("42")
      expect(page).to have_text("Not Tested")
    end

    it "handles zero domains needing service" do
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(0)

      render_inline(component)

      expect(page).to have_text("0")
      expect(page).to have_text("Not Tested")
    end
  end

  describe "progress display" do
    before do
      allow(Domain).to receive(:dns_active).and_return(double(count: 10))
      allow(Domain).to receive(:with_mx).and_return(double(count: 0))
      allow(Domain).to receive(:www_active).and_return(double(count: 0))
      allow(Domain).to receive(:with_web_content).and_return(double(count: 0))
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(5)
    end

    it "shows progress bar" do
      render_inline(component)

      expect(page).to have_text("Progress")
      expect(page).to have_css(".bg-blue-600") # Progress bar
    end

    it "shows tested domains count" do
      render_inline(component)

      expect(page).to have_text("domains tested")
    end
  end

  describe "styling and layout" do
    it "applies Flowbite card classes" do
      render_inline(component)

      expect(page).to have_css("div.p-6.bg-white.border.border-gray-200.rounded-lg.shadow")
      expect(page).to have_css("div.dark\\:bg-gray-800.dark\\:border-gray-700")
    end

    it "applies correct text styling for dark mode" do
      render_inline(component)

      expect(page).to have_css("h3.text-gray-900.dark\\:text-white")
      expect(page).to have_css("div.text-gray-600.dark\\:text-gray-400")
    end

    it "applies Flowbite form input styling" do
      render_inline(component)

      expect(page).to have_css("input.bg-gray-50.border.border-gray-300")
      expect(page).to have_css("input.focus\\:ring-blue-500.focus\\:border-blue-500")
      expect(page).to have_css("input.dark\\:bg-gray-700.dark\\:border-gray-600")
    end

    it "includes data attribute for service identification" do
      render_inline(component)

      expect(page).to have_css("div[data-service='domain_testing']")
    end
  end

  describe "with different service configurations" do
    before do
      # Setup mocks for MX testing
      allow(Domain).to receive_message_chain(:dns_active, :where).and_return(double(count: 0))
      allow(Domain).to receive_message_chain(:dns_active, :www_inactive, :count).and_return(0)
    end

    it "renders MX testing service correctly" do
      mx_component = described_class.new(
        service_name: "domain_mx_testing",
        title: "MX Testing",
        icon: "📧",
        action_path: "/domains/queue_mx_testing",
        queue_name: "domain_mx_testing"
      )

      render_inline(mx_component)

      expect(page).to have_css("h3", text: "MX Testing")
      expect(page).to have_text("📧")
      expect(page).to have_css("form[action='/domains/queue_mx_testing']")
      expect(page).to have_css("div[data-service='domain_mx_testing']")
    end

    it "renders A Record testing service correctly" do
      a_record_component = described_class.new(
        service_name: "domain_a_record_testing",
        title: "A Record Testing",
        icon: "🔍",
        action_path: "/domains/queue_a_record_testing",
        queue_name: "DomainARecordTestingService"
      )

      render_inline(a_record_component)

      expect(page).to have_css("h3", text: "A Record Testing")
      expect(page).to have_text("🔍")
      expect(page).to have_css("form[action='/domains/queue_a_record_testing']")
      expect(page).to have_css("div[data-service='domain_a_record_testing']")
    end
  end
end
