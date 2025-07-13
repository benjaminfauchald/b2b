# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phantom Buster Import Integration', type: :service do
  let(:user) { create(:user) }
  
  before do
    # Enable the person_import service
    ServiceConfiguration.find_or_create_by(service_name: 'person_import') do |config|
      config.active = true
      config.settings = {}
    end
  end
  let(:phantom_csv_content) do
    <<~CSV
      profileUrl,fullName,firstName,lastName,companyName,title,companyId,companyUrl,regularCompanyUrl,summary,titleDescription,industry,companyLocation,location,durationInRole,durationInCompany,pastExperienceCompanyName,pastExperienceCompanyUrl,pastExperienceCompanyTitle,pastExperienceDate,pastExperienceDuration,connectionDegree,profileImageUrl,sharedConnectionsCount,name,vmid,linkedInProfileUrl,isPremium,isOpenLink,query,timestamp,defaultProfileUrl
      "https://www.linkedin.com/in/test-integration",Integration Test User,Integration,Test User,Test Company AS,CTO,123456,https://linkedin.com/company/test-company,https://testcompany.no,"Bio text",,Technology,"Oslo, Norway","Oslo, Norway",2 years,3 years,Previous Corp,https://linkedin.com/company/previous,Developer,2019-2021,2 years,2nd,https://example.com/photo.jpg,150,Integration Test User,INT123,https://www.linkedin.com/in/test-integration,true,false,test query,2025-07-10T12:00:00Z,https://linkedin.com/in/test-integration
    CSV
  end
  
  let(:phantom_csv_file) do
    file = Tempfile.new(['phantom_buster', '.csv'])
    file.write(phantom_csv_content)
    file.rewind
    
    # Mock an uploaded file
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: 'phantom_buster_export.csv',
      type: 'text/csv'
    )
  end
  
  describe 'PersonImportService with Phantom Buster CSV' do
    subject(:service) { PersonImportService.new(file: phantom_csv_file, user: user, validate_emails: false) }
    
    it 'detects and processes Phantom Buster format' do
      result = service.perform
      
      puts "Result success: #{result.success?}"
      puts "Result error: #{result.error}"
      puts "Result data: #{result.data.inspect}"
      
      expect(result.success?).to be true
      expect(result.data[:imported]).to eq(1)
      expect(result.data[:failed]).to eq(0)
      
      # Check imported person has all fields mapped
      person = Person.last
      expect(person).to have_attributes(
        name: 'Integration Test User',
        first_name: 'Integration',
        last_name: 'Test User',
        company_name: 'Test Company AS',
        title: 'CTO',
        bio: 'Bio text',
        location: 'Oslo, Norway',
        company_location: 'Oslo, Norway',
        industry: 'Technology',
        duration_in_role: '2 years',
        duration_in_company: '3 years',
        past_experience_company_name: 'Previous Corp',
        past_experience_company_title: 'Developer',
        past_experience_date: '2019-2021',
        past_experience_duration: '2 years',
        shared_connections_count: 150,
        vmid: 'INT123',
        is_premium: true,
        is_open_link: false,
        query: 'test query',
        phantom_buster_timestamp: Time.parse('2025-07-10T12:00:00Z'),
        profile_url: 'https://www.linkedin.com/in/test-integration',
        import_tag: service.import_tag
      )
    end
    
    it 'handles duplicate profiles by updating' do
      # Create existing person
      existing = Person.create!(
        name: 'Old Name',
        profile_url: 'https://www.linkedin.com/in/test-integration',
        email: 'old@example.com'
      )
      
      result = service.perform
      
      expect(result.success?).to be true
      expect(result.data[:imported]).to eq(0)
      expect(result.data[:updated]).to eq(1)
      
      # Check person was updated
      existing.reload
      expect(existing.name).to eq('Integration Test User')
      expect(existing.title).to eq('CTO')
      expect(existing.is_premium).to be true
    end
    
    it 'falls back to standard CSV for non-Phantom Buster files' do
      standard_csv = Tempfile.new(['standard', '.csv'])
      standard_csv.write("Name,Email,Title,Company Name\nJohn Doe,john@example.com,Developer,ACME Corp")
      standard_csv.rewind
      
      standard_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: standard_csv,
        filename: 'standard.csv',
        type: 'text/csv'
      )
      
      service = PersonImportService.new(file: standard_file, user: user, validate_emails: false)
      result = service.perform
      
      expect(result.success?).to be true
      expect(result.data[:imported]).to eq(1)
      
      person = Person.last
      expect(person).to have_attributes(
        name: 'John Doe',
        email: 'john@example.com',
        title: 'Developer',
        company_name: 'ACME Corp'
      )
    end
  end
end