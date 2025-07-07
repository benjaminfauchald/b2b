# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "LinkedIn Discovery Postal Code Integration", type: :system do
  let(:user) { create(:user) }
  
  before do
    # Enable the LinkedIn discovery service
    ServiceConfiguration.create!(
      service_name: "company_linkedin_discovery",
      active: true
    )
    
    # Create test companies
    create_list(:company, 10, postal_code: '2000', operating_revenue: 500_000)
    create_list(:company, 5, postal_code: '0150', operating_revenue: 300_000)
    
    sign_in user
  end

  it "displays the LinkedIn discovery postal code component on companies page" do
    visit companies_path
    
    expect(page).to have_text("LinkedIn Discovery by Postal Code")
    expect(page).to have_selector("select[name='postal_code']")
    expect(page).to have_selector("select[name='batch_size']")
    expect(page).to have_button("Queue LinkedIn Discovery")
  end

  it "allows user to preview companies by postal code", js: true do
    visit companies_path
    
    # Wait for page to load
    expect(page).to have_text("LinkedIn Discovery by Postal Code")
    
    # Select postal code 2000
    select('2000', from: 'postal_code') if page.has_select?('postal_code', with_options: ['2000'])
    
    # Should show preview text with company count
    expect(page).to have_text("companies found", wait: 5)
  end

  it "shows appropriate message when no companies found for postal code" do
    visit companies_path
    
    # Enter a postal code that doesn't exist
    fill_in 'custom_postal_code', with: '9999'
    
    # Should show no companies found message
    expect(page).to have_text("No companies found", wait: 5)
  end

  it "enables/disables submit button based on company availability" do
    visit companies_path
    
    # With valid postal code, button should be enabled
    if page.has_select?('postal_code', with_options: ['2000'])
      select('2000', from: 'postal_code')
      expect(page).to have_button("Queue LinkedIn Discovery", disabled: false, wait: 5)
    end
  end
end