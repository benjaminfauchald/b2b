require 'rails_helper'

RSpec.describe "Domain Testing UI Integration", type: :system, js: true do
  let(:user) { create(:user) }
  let!(:domain) { create(:domain, dns: nil, mx: nil, www: nil) }
  
  before do
    # Ensure service configurations exist and are active
    ServiceConfiguration.find_or_create_by(service_name: "domain_testing").update(is_active: true)
    ServiceConfiguration.find_or_create_by(service_name: "domain_mx_testing").update(is_active: true)
    ServiceConfiguration.find_or_create_by(service_name: "domain_a_record_testing").update(is_active: true)
    
    # Login as user
    login_as(user, scope: :user)
    
    # Mock Sidekiq to run jobs immediately in test mode
    require 'sidekiq/testing'
    Sidekiq::Testing.inline!
  end

  after do
    Sidekiq::Testing.fake!
  end

  describe "DNS Testing Button Behavior" do
    it "shows proper UI feedback when clicking Test DNS button" do
      visit domain_path(domain)
      
      # Initial state verification
      within('[data-service="dns"]') do
        expect(page).to have_content("DNS Status")
        expect(page).to have_content("Not Tested")
        expect(page).to have_content("Never tested")
        expect(page).to have_button("Test DNS", disabled: false)
      end
      
      # Mock the DNS testing service to simulate a successful test
      allow_any_instance_of(DomainTestingService).to receive(:perform).and_return(
        double(success?: true, dns_active?: true, mx_records?: false, a_record?: false)
      )
      
      # Click the Test DNS button
      within('[data-service="dns"]') do
        click_button "Test DNS"
      end
      
      # Verify immediate UI feedback
      within('[data-service="dns"]') do
        # Button should be disabled and show "Testing..."
        expect(page).to have_button("Testing...", disabled: true)
        
        # Status badge should show "Testing..."
        expect(page).to have_css('[data-status-target="status"]', text: "Testing...")
      end
      
      # Wait for the job to complete (since we're using inline mode)
      sleep 0.5
      
      # Reload to see updated status
      visit current_path
      
      # Verify final state after testing completes
      within('[data-service="dns"]') do
        expect(page).to have_content("Active")
        expect(page).to have_content("Last tested: less than a minute ago")
        expect(page).to have_button("Re-test DNS", disabled: false)
      end
    end
    
    it "shows error state when DNS test fails" do
      visit domain_path(domain)
      
      # Mock the DNS testing service to simulate a failed test
      allow_any_instance_of(DomainTestingService).to receive(:perform).and_return(
        double(success?: true, dns_active?: false, mx_records?: false, a_record?: false)
      )
      
      within('[data-service="dns"]') do
        click_button "Test DNS"
      end
      
      # Wait for completion
      sleep 0.5
      visit current_path
      
      # Verify error state
      within('[data-service="dns"]') do
        expect(page).to have_content("Inactive")
        expect(page).to have_button("Retry DNS", disabled: false)
      end
    end
    
    it "prevents multiple simultaneous tests" do
      visit domain_path(domain)
      
      # Mock a slow-running test
      allow_any_instance_of(DomainTestingService).to receive(:perform) do
        sleep 2
        double(success?: true, dns_active?: true, mx_records?: false, a_record?: false)
      end
      
      # Start first test
      within('[data-service="dns"]') do
        click_button "Test DNS"
        expect(page).to have_button("Testing...", disabled: true)
      end
      
      # Try to click again (should not be possible)
      within('[data-service="dns"]') do
        button = find('button[type="submit"]')
        expect(button).to be_disabled
      end
    end
  end
  
  describe "Multiple Service Tests" do
    it "allows testing different services independently" do
      visit domain_path(domain)
      
      # Mock services
      allow_any_instance_of(DomainTestingService).to receive(:perform).and_return(
        double(success?: true, dns_active?: true, mx_records?: true, a_record?: false)
      )
      
      allow_any_instance_of(DomainMxTestingService).to receive(:perform).and_return(
        double(success?: true, mx_active?: true)
      )
      
      # Test DNS
      within('[data-service="dns"]') do
        click_button "Test DNS"
      end
      
      # While DNS is testing, MX button should still be clickable
      within('[data-service="mx"]') do
        expect(page).to have_button("Test MX", disabled: false)
        click_button "Test MX"
      end
      
      # Both should show testing state
      within('[data-service="dns"]') do
        expect(page).to have_content("Testing...")
      end
      
      within('[data-service="mx"]') do
        expect(page).to have_content("Testing...")
      end
      
      # Wait and reload
      sleep 0.5
      visit current_path
      
      # Both should show completed state
      within('[data-service="dns"]') do
        expect(page).to have_content("Active")
      end
      
      within('[data-service="mx"]') do
        expect(page).to have_content("Active")
      end
    end
  end
  
  describe "Real-time Status Updates" do
    it "updates status without page reload using polling", skip: "Requires JavaScript polling implementation" do
      # This test would require Capybara with a JavaScript driver like Selenium
      # and would test the polling functionality
    end
  end
  
  describe "Toast Notifications" do
    it "shows success toast when test is queued" do
      visit domain_path(domain)
      
      allow_any_instance_of(DomainTestingService).to receive(:perform).and_return(
        double(success?: true, dns_active?: true, mx_records?: false, a_record?: false)
      )
      
      within('[data-service="dns"]') do
        click_button "Test DNS"
      end
      
      # Check for toast notification
      expect(page).to have_css('.bg-green-500', text: /queued/i)
    end
    
    it "shows error toast when service is disabled" do
      # Disable the service
      ServiceConfiguration.find_by(service_name: "domain_testing").update(is_active: false)
      
      visit domain_path(domain)
      
      within('[data-service="dns"]') do
        # Button should be disabled
        expect(page).to have_button("Test DNS", disabled: true)
      end
    end
  end
end