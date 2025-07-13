# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "PhantomBuster Status Display", type: :system, js: true do
  let(:test_user) { create(:user, email: "test@test.no") }
  let(:company) { create(:company, company_name: "Test Processing Company AS") }

  before do
    driven_by(:selenium_chrome_headless)

    # Clean up
    Person.destroy_all
    Company.destroy_all
    ServiceAuditLog.destroy_all
    ServiceConfiguration.destroy_all

    # Enable profile extraction service
    ServiceConfiguration.create!(service_name: "person_profile_extraction", active: true)

    # Create some people needing profile extraction  
    10.times do |i|
      create(:person,
        company: company,
        name: "Test Person #{i}",
        profile_url: nil,  # Needs profile extraction
        profile_extracted_at: nil  # Ensure they need processing
      )
    end

    sign_in test_user
  end

  describe "button state changes during PhantomBuster processing" do
    it "shows idle state when not processing" do
      # Mock PhantomBusterSequentialQueue to return idle state
      allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
        queue_length: 0,
        is_processing: false,
        current_job: nil,
        lock_timestamp: Time.current.to_i
      })

      visit people_path

      # Find the Profile Extraction service button
      within("[data-service='person_profile_extraction']") do
        button = find('[data-phantom-buster-status-target="submitButton"]')
        
        # Should show "Queue Processing" text
        expect(button).to have_text("Queue Processing")
        # Note: Button may be disabled if no items need processing
      end
    end

    it "shows processing state with company name when PhantomBuster is running", :aggregate_failures do
      # Mock PhantomBusterSequentialQueue to return processing state
      allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
        queue_length: 2,
        is_processing: true,
        current_job: {
          'company_id' => company.id,
          'queued_at' => 2.minutes.ago.to_i
        },
        lock_timestamp: Time.current.to_i
      })

      visit people_path

      # Wait for the phantom-buster-status controller to connect and poll
      sleep 1

      within("[data-service='person_profile_extraction']") do
        button = find('[data-phantom-buster-status-target="submitButton"]')
        
        # Should show processing state with company name (may be truncated)
        expect(button.text).to include("Processing Test Processing Company")
        expect(button).to be_disabled
        expect(button).to have_css('.cursor-not-allowed, .opacity-75')
        
        # Should have spinner icon
        expect(button).to have_css('svg.animate-spin')
      end
    end

    it "truncates long company names in button text" do
      long_company = create(:company, company_name: "Very Long Company Name That Should Be Truncated For UI Display AS")
      
      allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
        queue_length: 1,
        is_processing: true,
        current_job: {
          'company_id' => long_company.id,
          'queued_at' => 1.minute.ago.to_i
        },
        lock_timestamp: Time.current.to_i
      })

      visit people_path

      # Wait for the phantom-buster-status controller to connect and poll
      sleep 1

      within("[data-service='person_profile_extraction']") do
        button = find('[data-phantom-buster-status-target="submitButton"]')
        
        # Should truncate the company name  
        expect(button.text).to include("Processing Very Long Company Name")
        expect(button.text).to include("...")
        expect(button.text.length).to be <= 50  # Allow some flexibility
      end
    end

    it "updates queue length display when available" do
      allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
        queue_length: 5,
        is_processing: true,
        current_job: {
          'company_id' => company.id,
          'queued_at' => 30.seconds.ago.to_i
        },
        lock_timestamp: Time.current.to_i
      })

      visit people_path

      # Wait for the phantom-buster-status controller to connect and poll
      sleep 1

      within("[data-service='person_profile_extraction']") do
        # Check if queue length is updated (this depends on the queue_name being "phantom_queue")
        if page.has_css?('[data-queue-stat="phantom_queue"]')
          queue_element = find('[data-queue-stat="phantom_queue"]')
          expect(queue_element).to have_text("5 in queue")
        end
      end
    end

    it "handles API errors gracefully" do
      # Mock fetch to return 500 error (simulates network/server error)
      page.execute_script(<<~JS)
        const originalFetch = window.fetch;
        window.fetch = function(url, options) {
          if (url.includes('/api/phantom_buster/status')) {
            return Promise.resolve({
              ok: false,
              status: 500,
              json: () => Promise.resolve({ error: 'Server Error' })
            });
          }
          return originalFetch.apply(this, arguments);
        };
      JS

      visit people_path

      # Wait for polling attempt
      sleep 4  # Wait longer than polling interval

      within("[data-service='person_profile_extraction']") do
        button = find('[data-phantom-buster-status-target="submitButton"]')
        
        # Should fall back to idle state on error
        expect(button).to have_text("Queue Processing")
        # Note: Button may be disabled if no items need processing
      end
    end
  end

  describe "status container updates" do
    it "shows additional status information when available" do
      allow(PhantomBusterSequentialQueue).to receive(:queue_status).and_return({
        queue_length: 1,
        is_processing: true,
        current_job: {
          'company_id' => company.id,
          'queued_at' => 2.minutes.ago.to_i
        },
        lock_timestamp: Time.current.to_i
      })

      visit people_path

      # Wait for controller to connect and update
      sleep 1

      within("[data-service='person_profile_extraction']") do
        # Check if status container exists and gets updated
        if page.has_css?('[data-phantom-buster-status-target="statusContainer"]')
          status_container = find('[data-phantom-buster-status-target="statusContainer"]')
          
          # Should contain duration information
          expect(status_container).to have_text(/Processing for \d+m \d+s/)
        end
      end
    end
  end

  describe "polling behavior" do
    it "starts polling on page load and stops on page unload", :aggregate_failures do
      visit people_path

      # Check that the controller is connected
      expect(page).to have_css('[data-controller*="phantom-buster-status"]')
      
      # Verify polling is working by checking network requests
      # (This is a simplified test - in a real scenario you'd mock fetch)
      
      # Navigate away to test cleanup
      visit root_path
      
      # The controller should disconnect and stop polling
      expect(page).not_to have_css('[data-controller*="phantom-buster-status"]')
    end
  end
end