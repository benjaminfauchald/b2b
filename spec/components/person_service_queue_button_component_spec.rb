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
    # Mock Sidekiq queue - PersonServiceQueueButtonComponent returns 0 for mock services
    allow(Sidekiq::Queue).to receive(:new).with(queue_name).and_return(
      double(size: 0)
    )
  end

  describe "rendering" do
    it "renders the component with title and form" do
      # Create people that need profile extraction
      create(:person, name: "Test Person 1", profile_data: nil)
      create(:person, name: "Test Person 2", profile_data: nil)

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
    before do
      # Clear existing people and audit logs first
      Person.destroy_all
      ServiceAuditLog.destroy_all
    end

    let!(:people_needing) do
      [
        create(:person, name: "Person 1", profile_data: nil),
        create(:person, name: "Person 2", profile_data: nil)
      ]
    end

    let!(:people_not_needing) do
      [
        create(:person, name: "Person 3", profile_data: { some: "data" }),
        create(:person, name: "Person 4", profile_data: { other: "data" })
      ]
    end

    describe "#people_needing_service" do
      it "returns count of people needing profile extraction" do
        expect(component.send(:people_needing_service)).to eq(2)
      end
    end

    describe "#profile_extraction_potential" do
      it "returns total potential people for profile extraction" do
        # All people are potential for extraction
        expect(component.send(:profile_extraction_potential)).to eq(4)
      end
    end

    describe "#people_completed" do
      it "returns count of people with successful profile extraction" do
        # people_not_needing already have profile_data, so they are completed
        expect(component.send(:people_completed)).to eq(2)
      end
    end

    describe "#completion_percentage" do
      it "calculates correct completion percentage" do
        # 2 completed out of 4 potential = 50%
        expect(component.send(:completion_percentage)).to eq(50)
      end

      context "when completion is less than 1%" do
        before do
          # Create 300 more people without profile data to make percentage < 1%
          # 2 completed out of 304 total = 0.66%
          300.times do |i|
            create(:person, name: "Person #{i + 100}", profile_data: nil)
          end
        end

        it "returns percentage with 1 decimal place" do
          percentage = component.send(:completion_percentage)
          expect(percentage).to be < 1
          expect(percentage).to eq(0.7) # 2/304 * 100 = 0.657... rounds to 0.7
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
    before do
      # Clean up all people and audit logs to ensure test isolation
      Person.destroy_all
      ServiceAuditLog.destroy_all
    end

    let!(:people) do
      3.times.map do |i|
        create(:person, name: "Person #{i}", profile_data: nil)
      end
    end

    before do
      # Mark 1 out of 3 as completed (33.33%)
      people.first.update!(profile_data: { extracted: true })
    end

    it "renders progress bar with correct percentage" do
      render_inline(component)

      expect(page).to have_text("Profile Extraction Completion")
      expect(page).to have_text("33%")
      expect(page).to have_css(".bg-blue-600[style*='width: 33%']")
      expect(page).to have_text("1 of 3 people processed")
    end
  end

  describe "form behavior" do
    before do
      # Clean up all people to ensure test isolation
      Person.destroy_all
    end

    let!(:people) { 2.times.map { |i| create(:person, name: "Person #{i}", profile_data: nil) } }

    it "sets correct default and max values for batch size input" do
      render_inline(component)

      input = page.find("input[name='count']")
      expect(input.value).to eq("2") # min of people_needing (2) and 100
      expect(input["max"]).to eq("2") # min of people_needing (2) and 1000
      expect(input["data-max-available"]).to eq("2")
    end

    context "when many people need processing" do
      before do
        # Already have 2 people from parent context
        150.times { |i| create(:person, name: "Person #{i + 100}", profile_data: nil) }
      end

      it "limits default value to 100" do
        render_inline(component)

        input = page.find("input[name='count']")
        expect(input.value).to eq("100") # min of people_needing (152) and 100
        expect(input["max"]).to eq("152") # min of people_needing (152) and 1000
      end
    end
  end

  describe "other services" do
    context "email extraction service" do
      let(:service_name) { "person_email_extraction" }
      let(:icon) { "email" }

      before do
        Person.destroy_all
      end

      it "counts people needing email extraction correctly" do
        create(:person, name: "No Email", email: nil)
        create(:person, name: "Empty Email", email: "")
        create(:person, name: "Has Email", email: "test@example.com")

        expect(component.send(:people_needing_service)).to eq(2)
      end

      it "counts completed email extractions correctly" do
        create(:person, name: "No Email", email: nil)
        create(:person, name: "Has Email", email: "test@example.com")

        expect(component.send(:people_completed)).to eq(1)
      end
    end

    context "social media extraction service" do
      let(:service_name) { "person_social_media_extraction" }
      let(:icon) { "social" }

      before do
        Person.destroy_all
      end

      it "counts people needing social media extraction correctly" do
        create(:person, name: "No Social", social_media_data: nil)
        create(:person, name: "Has Social", social_media_data: { twitter: "@test" })

        expect(component.send(:people_needing_service)).to eq(1)
      end

      it "counts completed social media extractions correctly" do
        create(:person, name: "No Social", social_media_data: nil)
        create(:person, name: "Has Social", social_media_data: { twitter: "@test" })

        expect(component.send(:people_completed)).to eq(1)
      end
    end
  end
end
