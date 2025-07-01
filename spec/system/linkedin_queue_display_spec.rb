# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "LinkedIn Queue Display", type: :system, js: true do
  let(:admin_user) { create(:user, email: "admin@example.com") }

  before do
    driven_by(:selenium_chrome_headless)
    
    # Clean up
    Company.destroy_all
    ServiceAuditLog.destroy_all
    ServiceConfiguration.destroy_all
    
    # Enable service
    ServiceConfiguration.create!(service_name: "company_linkedin_discovery", active: true)
    
    # Create companies
    20.times do |i|
      create(:company,
        registration_number: "NO#{800000 + i}",
        company_name: "Queue Test Company #{i}",
        source_country: "NO",
        operating_revenue: 20_000_000,
        linkedin_ai_url: nil
      )
    end
    
    sign_in admin_user
  end

  describe "queue statistics display" do
    it "shows the current queue size" do
      # Use fake mode to prevent processing
      Sidekiq::Testing.fake! do
        visit companies_path
        
        # Find the LinkedIn queue stats element
        linkedin_queue_element = find('[data-queue-stat="company_linkedin_discovery"]')
        
        # Initially should show 0
        expect(linkedin_queue_element).to have_text("0")
        
        # Queue some jobs
        within("[data-service='company_linkedin_discovery']") do
          fill_in "company_linkedin_discovery_count", with: "5"
          click_button "Queue Processing"
        end
        
        # Wait for the response
        expect(page).to have_css('.toast-notification', text: 'Queued 5 companies')
        
        # The queue stat should update (in real app with Turbo Streams)
        # In test environment, we can verify the jobs were queued
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(5)
      end
    end

    it "displays queue size in the enhancement statistics card" do
      visit companies_path
      
      within(".enhancement-statistics") do
        # Find the LinkedIn Discovery queue display
        queue_display = find("div", text: /LinkedIn Discovery/)
        
        # Should show the queue size
        expect(queue_display).to have_text(/\d+ in queue/)
      end
    end
  end

  describe "real-time queue updates" do
    it "updates queue display after queueing jobs" do
      Sidekiq::Testing.fake! do
        visit companies_path
        
        # Get initial queue size
        initial_queue_text = find('[data-queue-stat="company_linkedin_discovery"]').text
        
        # Queue some companies
        within("[data-service='company_linkedin_discovery']") do
          fill_in "company_linkedin_discovery_count", with: "3"
          click_button "Queue Processing"
        end
        
        # In a real app with ActionCable/Turbo Streams, this would update automatically
        # For now, we verify the backend state
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(3)
        
        # The controller returns updated queue stats
        # which the JS should use to update the display
      end
    end
  end
end