require 'rails_helper'
require 'sidekiq/api'

RSpec.describe PersonServiceQueueButtonComponent, type: :component do
  let(:service_name) { "person_profile_extraction" }
  let(:title) { "Profile Extraction" }
  let(:icon) { "user-group" }
  let(:action_path) { "/people/queue_profile_extraction" }
  let(:queue_name) { "person_profile_extraction" }

  let(:component) do
    PersonServiceQueueButtonComponent.new(
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

  describe "rendering" do
    it "renders the component with title and form" do
      render_inline(component)
      
      expect(page).to have_text(title)
      expect(page).to have_css("form[action='#{action_path}']")
      expect(page).to have_css("input[name='count']")
      expect(page).to have_button("Queue Processing")
    end

    it "includes service queue controller data attributes" do
      render_inline(component)
      
      expect(page).to have_css("[data-controller='service-queue']")
      expect(page).to have_css("[data-service-queue-service-name-value='#{service_name}']")
    end
  end

  describe "progress tracking" do
    let!(:companies_needing) do
      [
        create(:company, linkedin_url: "https://linkedin.com/company/test1"),
        create(:company, linkedin_ai_url: "https://linkedin.com/company/test2", linkedin_ai_confidence: 85)
      ]
    end

    let!(:companies_not_needing) do
      [
        create(:company, linkedin_ai_url: "https://linkedin.com/company/low", linkedin_ai_confidence: 70),
        create(:company, linkedin_url: nil, linkedin_ai_url: nil)
      ]
    end

    describe "#companies_needing_service" do
      it "returns count of companies needing profile extraction" do
        expect(component.send(:companies_needing_service)).to eq(2)
      end
    end

    describe "#profile_extraction_potential" do
      it "returns total potential companies for profile extraction" do
        expect(component.send(:profile_extraction_potential)).to eq(2)
      end
    end

    describe "#companies_completed" do
      before do
        # Create successful audit logs for some companies
        create(:service_audit_log,
          auditable: companies_needing.first,
          auditable_type: "Company",
          service_name: "person_profile_extraction",
          status: "success"
        )
      end

      it "returns count of companies with successful profile extraction" do
        expect(component.send(:companies_completed)).to eq(1)
      end
    end

    describe "#completion_percentage" do
      before do
        # Create successful audit logs for one company
        create(:service_audit_log,
          auditable: companies_needing.first,
          auditable_type: "Company",
          service_name: "person_profile_extraction",
          status: "success"
        )
      end

      it "calculates correct completion percentage" do
        # 1 completed out of 2 potential = 50%
        expect(component.send(:completion_percentage)).to eq(50)
      end

      context "when completion is less than 1%" do
        before do
          # Create 200 more companies to make percentage < 1%
          200.times do
            create(:company, linkedin_url: "https://linkedin.com/company/test#{rand(10000)}")
          end
        end

        it "returns percentage with 1 decimal place" do
          percentage = component.send(:completion_percentage)
          expect(percentage).to be < 1
          expect(percentage.to_s).to match(/\A\d+\.\d\z/) # Format: X.X
        end
      end
    end

    describe "#show_completion_percentage?" do
      it "returns true for person_profile_extraction service" do
        expect(component.send(:show_completion_percentage?)).to be true
      end

      it "returns false for other services" do
        other_component = PersonServiceQueueButtonComponent.new(
          service_name: "other_service",
          title: "Other",
          icon: "search",
          action_path: "/other",
          queue_name: "other"
        )
        
        expect(other_component.send(:show_completion_percentage?)).to be false
      end
    end
  end

  describe "progress bar rendering" do
    let!(:companies) do
      3.times.map do |i|
        create(:company, linkedin_url: "https://linkedin.com/company/test#{i}")
      end
    end

    before do
      # Mark 1 out of 3 as completed (33.33%)
      create(:service_audit_log,
        auditable: companies.first,
        auditable_type: "Company",
        service_name: "person_profile_extraction",
        status: "success"
      )
    end

    it "renders progress bar with correct percentage" do
      render_inline(component)
      
      expect(page).to have_text("Profile Extraction Completion")
      expect(page).to have_text("33%")
      expect(page).to have_css(".bg-blue-600[style*='width: 33%']")
      expect(page).to have_text("1 of 3 companies processed")
    end
  end

  describe "form behavior" do
    let!(:companies) { 2.times.map { create(:company, linkedin_url: "https://test.com") } }

    it "sets correct default and max values for batch size input" do
      render_inline(component)
      
      input = page.find("input[name='count']")
      expect(input.value).to eq("2") # min of companies_needing (2) and 100
      expect(input["max"]).to eq("2") # min of companies_needing (2) and 1000
      expect(input["data-max-available"]).to eq("2")
    end

    context "when many companies need processing" do
      before do
        150.times { create(:company, linkedin_url: "https://test#{rand(1000)}.com") }
      end

      it "limits default value to 100" do
        render_inline(component)
        
        input = page.find("input[name='count']")
        expect(input.value).to eq("100") # min of companies_needing (152) and 100
        expect(input["max"]).to eq("152") # min of companies_needing (152) and 1000
      end
    end
  end
end