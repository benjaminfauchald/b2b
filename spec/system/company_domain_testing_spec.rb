require 'rails_helper'

RSpec.describe "Company Domain Testing", type: :system, js: true do
  let(:user) { create(:user, email: 'test@example.com', password: 'password123') }
  let(:company) { create(:company, website: nil) }

  before do
    login_as(user, scope: :user)
    
    # Mock service configurations as active
    allow(ServiceConfiguration).to receive(:active?).and_return(true)
  end

  describe 'adding website to company triggers domain tests' do
    it 'creates domain and shows testing status' do
      visit company_path(company)
      
      # Click edit button
      click_button 'Edit'
      
      # Fill in website
      fill_in 'Website', with: 'example.com'
      click_button 'Save Changes'
      
      # Expect to see success message
      expect(page).to have_content('Company was successfully updated')
      
      # Check that domain test status badges appear
      # Look specifically within the domain test status component
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('span', text: 'DNS')
        expect(page).to have_css('span', text: 'MX')
        expect(page).to have_css('span', text: 'A Record')
        
        # Should show testing animation
        expect(page).to have_css('.animate-pulse')
      end
      
      # Verify domain was created
      company.reload
      expect(company.domain).to be_present
      expect(company.domain.domain).to eq('example.com')
    end
  end

  describe 'domain test status updates' do
    let!(:domain) { create(:domain, company: company, domain: 'test.com', dns: nil, mx: nil, www: nil) }

    before do
      company.update!(website: 'test.com')
    end

    it 'shows real-time status updates via polling' do
      visit company_path(company)
      
      # Initially shows testing status
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('span.animate-pulse', text: /DNS/)
      end
      
      # Simulate DNS test completion
      domain.update!(dns: true)
      
      # Manually trigger page refresh to simulate polling update
      page.refresh
      
      # Should now show completed DNS status
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('span.bg-green-100', text: /DNS/)
        
        # MX and A Record should still be testing
        expect(page).to have_css('span.animate-pulse', text: /MX/)
        expect(page).to have_css('span.animate-pulse', text: /A Record/)
      end
    end

    it 'stops polling when all tests complete' do
      visit company_path(company)
      
      # Complete all tests
      domain.update!(dns: true, mx: true, www: false)
      
      # Refresh to see updated status
      page.refresh
      
      # Should show final status without animation
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('span.bg-green-100', text: /DNS/)
        expect(page).to have_css('span.bg-green-100', text: /MX/)
        expect(page).to have_css('span.bg-red-100', text: /A Record/)
        
        # No more pulsing animations
        expect(page).not_to have_css('.animate-pulse')
      end
    end

    it 'shows skipped status when DNS fails' do
      visit company_path(company)
      
      # DNS test fails
      domain.update!(dns: false)
      
      # Refresh to see updated status
      page.refresh
      
      # Should show error for DNS and skipped for others
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('span.bg-red-100', text: /DNS/)
        expect(page).to have_css('span.bg-gray-100.text-gray-500', text: /MX/)
        expect(page).to have_css('span.bg-gray-100.text-gray-500', text: /A Record/)
      end
    end
  end

  describe 'domain normalization' do
    it 'handles various URL formats' do
      visit company_path(company)
      
      # Test with full URL
      click_button 'Edit'
      fill_in 'Website', with: 'https://www.example.com/path?query=1'
      click_button 'Save Changes'
      
      company.reload
      expect(company.domain.domain).to eq('example.com')
      expect(page).to have_link('https://www.example.com/path?query=1')
    end
  end

  describe 'invalid domain handling' do
    it 'does not create domain for invalid input' do
      visit company_path(company)
      
      click_button 'Edit'
      fill_in 'Website', with: 'not a domain'
      click_button 'Save Changes'
      
      company.reload
      expect(company.domain).to be_nil
      expect(page).not_to have_css('span', text: 'DNS')
    end
  end

  describe 'updating existing domain' do
    let!(:domain) { create(:domain, company: company, domain: 'old.com', dns: true, mx: true, www: true) }

    before do
      company.update!(website: 'old.com')
    end

    it 'resets test results when domain changes' do
      visit company_path(company)
      
      # Should show completed tests
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('.bg-green-100', count: 3)
      end
      
      # Update domain
      click_button 'Edit'
      fill_in 'Website', with: 'new.com'
      click_button 'Save Changes'
      
      # Should reset to testing status
      within '[data-controller="domain-test-status"]' do
        expect(page).to have_css('span.animate-pulse', text: /DNS/)
        expect(page).to have_css('span.animate-pulse', text: /MX/)
        expect(page).to have_css('span.animate-pulse', text: /A Record/)
      end
      
      # Verify domain was updated
      domain.reload
      expect(domain.domain).to eq('new.com')
      expect(domain.dns).to be_nil
      expect(domain.mx).to be_nil
      expect(domain.www).to be_nil
    end
  end
end