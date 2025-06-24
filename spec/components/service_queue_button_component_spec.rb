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
      render_inline(component)

      expect(page).to have_field("count", with: "100")
      expect(page).to have_css("input[type='number'][min='1'][max='1000']")
    end

    it "renders submit button with Flowbite styling" do
      render_inline(component)

      expect(page).to have_button("Queue Testing")
      expect(page).to have_css("button.text-white.bg-blue-700.hover\\:bg-blue-800")
      expect(page).to have_css("button.focus\\:ring-4.focus\\:ring-blue-300")
      expect(page).to have_css("button.font-medium.rounded-lg")
    end
  end

  describe "domains needing service" do
    it "shows count of domains needing service" do
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(42)

      render_inline(component)

      expect(page).to have_text("42 domains need testing")
    end

    it "handles zero domains needing service" do
      allow(Domain).to receive_message_chain(:needing_service, :count).and_return(0)

      render_inline(component)

      expect(page).to have_text("0 domains need testing")
    end
  end

  describe "queue status" do
    it "shows current queue depth" do
      queue = double(size: 10)
      allow(Sidekiq::Queue).to receive(:new).with("domain_dns_testing").and_return(queue)

      render_inline(component)

      expect(page).to have_text("10 in queue")
    end

    it "shows zero when queue is empty" do
      queue = double(size: 0)
      allow(Sidekiq::Queue).to receive(:new).with("domain_dns_testing").and_return(queue)

      render_inline(component)

      expect(page).to have_text("0 in queue")
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