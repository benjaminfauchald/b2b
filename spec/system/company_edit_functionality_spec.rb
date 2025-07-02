require 'rails_helper'

RSpec.describe 'Company Edit Functionality', type: :system do
  let(:user) { create(:user) }
  let(:company) do
    create(:company,
      company_name: 'Test Company AS',
      registration_number: '123456789',
      website: 'https://oldwebsite.com',
      email: 'old@example.com',
      phone: '+47 111 22 333',
      linkedin_url: nil
    )
  end

  before do
    login_as(user, scope: :user)
  end

  describe 'editing company information' do
    it 'shows the edit button on company page' do
      visit company_path(company)

      # Find the Company Information section specifically
      company_info_section = find('h2', text: 'Company Information').ancestor('.bg-white.border.border-gray-200.rounded-lg.shadow-sm')
      within(company_info_section) do
        expect(page).to have_content('Company Information')
        expect(page).to have_button('Edit')
      end
    end

    it 'toggles the edit form when clicking Edit button' do
      visit company_path(company)

      # Initially, form should be hidden and data displayed
      expect(page).to have_content('https://oldwebsite.com')
      expect(page).to have_content('old@example.com')
      expect(page).not_to have_field('company[website]')

      # Click Edit button
      click_button 'Edit'

      # Form should be visible with current values
      expect(page).to have_field('company[website]', with: 'https://oldwebsite.com')
      expect(page).to have_field('company[email]', with: 'old@example.com')
      expect(page).to have_field('company[phone]', with: '+47 111 22 333')
      expect(page).to have_field('company[linkedin_url]', with: '')
      expect(page).to have_button('Save Changes')
      expect(page).to have_button('Cancel')
    end

    it 'updates company fields and creates audit log' do
      visit company_path(company)
      click_button 'Edit'

      # Fill in new values
      fill_in 'company[website]', with: 'https://newwebsite.com'
      fill_in 'company[email]', with: 'new@example.com'
      fill_in 'company[phone]', with: '+47 999 88 777'
      fill_in 'company[linkedin_url]', with: 'https://linkedin.com/company/testcompany'

      # Submit form
      click_button 'Save Changes'

      # Wait for page reload
      expect(page).to have_current_path(company_path(company))

      # Verify updated values are displayed
      expect(page).to have_link('https://newwebsite.com', href: 'https://newwebsite.com')
      expect(page).to have_link('new@example.com', href: 'mailto:new@example.com')
      expect(page).to have_content('+47 999 88 777')
      expect(page).to have_link('linkedin/testcompany', href: 'https://linkedin.com/company/testcompany')

      # Verify audit log was created
      audit_log = ServiceAuditLog.where(
        auditable: company,
        service_name: 'user_update'
      ).last

      expect(audit_log).to be_present
      expect(audit_log.columns_affected).to contain_exactly('website', 'email', 'phone', 'linkedin_url')
      expect(audit_log.metadata['updated_by']).to eq(user.email)
    end

    it 'cancels editing without saving changes' do
      visit company_path(company)
      click_button 'Edit'

      # Change values
      fill_in 'company[website]', with: 'https://shouldnotbesaved.com'

      # Click Cancel
      within('#company-edit-form') do
        click_button 'Cancel'
      end

      # Verify original values are still displayed
      expect(page).to have_content('https://oldwebsite.com')
      expect(page).not_to have_content('https://shouldnotbesaved.com')

      # Verify no audit log was created
      expect(ServiceAuditLog.where(auditable: company, service_name: 'user_update').count).to eq(0)
    end

    it 'only updates changed fields in audit log' do
      visit company_path(company)
      click_button 'Edit'

      # Only change website and email
      fill_in 'company[website]', with: 'https://updated.com'
      fill_in 'company[email]', with: 'updated@example.com'
      # Leave phone and linkedin_url unchanged

      click_button 'Save Changes'

      # Check audit log only contains changed fields
      audit_log = ServiceAuditLog.last
      expect(audit_log.columns_affected).to contain_exactly('website', 'email')
      expect(audit_log.metadata['changes']['website']).to eq({
        'old_value' => 'https://oldwebsite.com',
        'new_value' => 'https://updated.com'
      })
      expect(audit_log.metadata['changes']['email']).to eq({
        'old_value' => 'old@example.com',
        'new_value' => 'updated@example.com'
      })
    end

    it 'displays success message after update' do
      visit company_path(company)
      click_button 'Edit'

      fill_in 'company[website]', with: 'https://success.com'
      click_button 'Save Changes'

      expect(page).to have_content('Company was successfully updated.')
    end
  end

  describe 'ServiceAuditLog compliance' do
    it 'creates fully compliant audit log entries' do
      visit company_path(company)
      click_button 'Edit'

      fill_in 'company[website]', with: 'https://compliant.com'

      # Record the time before submission
      time_before = Time.current

      click_button 'Save Changes'

      audit_log = ServiceAuditLog.last

      # Verify all required fields
      expect(audit_log.auditable_type).to eq('Company')
      expect(audit_log.auditable_id).to eq(company.id)
      expect(audit_log.service_name).to eq('user_update')
      expect(audit_log.status).to eq('success')
      expect(audit_log.table_name).to eq('companies')
      expect(audit_log.record_id).to eq(company.id.to_s)
      expect(audit_log.operation_type).to eq('update')
      expect(audit_log.columns_affected).to include('website')
      expect(audit_log.execution_time_ms).to eq(0)

      # Verify timestamps
      expect(audit_log.started_at).to be >= time_before
      expect(audit_log.completed_at).to be >= audit_log.started_at
      expect(audit_log.completed_at - audit_log.started_at).to be < 1.second

      # Verify metadata
      expect(audit_log.metadata).to be_a(Hash)
      expect(audit_log.metadata['updated_by']).to eq(user.email)
      expect(audit_log.metadata['updated_at']).to be_present
      expect(Time.parse(audit_log.metadata['updated_at'])).to be_within(5.seconds).of(Time.current)
    end
  end
end
