# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhantomBusterImportService, type: :service do
  let(:valid_csv_path) { Rails.root.join('tmp', 'phantom_buster_test.csv') }
  let(:invalid_csv_path) { Rails.root.join('tmp', 'invalid_test.csv') }
  
  let(:valid_csv_content) do
    <<~CSV
      profileUrl,fullName,firstName,lastName,companyName,title,companyId,companyUrl,regularCompanyUrl,summary,titleDescription,industry,companyLocation,location,durationInRole,durationInCompany,pastExperienceCompanyName,pastExperienceCompanyUrl,pastExperienceCompanyTitle,pastExperienceDate,pastExperienceDuration,connectionDegree,profileImageUrl,sharedConnectionsCount,name,vmid,linkedInProfileUrl,isPremium,isOpenLink,query,timestamp,defaultProfileUrl
      "https://www.linkedin.com/in/test-user-1",Test User One,Test,User One,Test Company,Software Engineer,12345,https://www.linkedin.com/company/test-company,https://testcompany.com,"Test bio",,Technology,"Oslo, Norway","Oslo, Norway",2 years,3 years,Previous Company,https://linkedin.com/company/previous,Senior Developer,2020-2021,1 year,2nd,https://example.com/photo.jpg,50,Test User One,TEST123,https://www.linkedin.com/in/test-user-1,true,false,test query,2025-07-10T10:00:00Z,https://linkedin.com/in/test-user-1
      "https://www.linkedin.com/in/test-user-2",Test User Two,Test,User Two,Another Company,Product Manager,67890,https://www.linkedin.com/company/another-company,https://anothercompany.com,"Another bio",,Finance,"Bergen, Norway","Bergen, Norway",1 year,1 year,,,,,,3rd,https://example.com/photo2.jpg,25,Test User Two,TEST456,https://www.linkedin.com/in/test-user-2,false,true,test query,2025-07-10T11:00:00Z,https://linkedin.com/in/test-user-2
    CSV
  end
  
  let(:invalid_csv_content) do
    <<~CSV
      name,email,phone
      John Doe,john@example.com,123-456-7890
      Jane Smith,jane@example.com,098-765-4321
    CSV
  end
  
  before do
    File.write(valid_csv_path, valid_csv_content)
    File.write(invalid_csv_path, invalid_csv_content)
  end
  
  after do
    File.delete(valid_csv_path) if File.exist?(valid_csv_path)
    File.delete(invalid_csv_path) if File.exist?(invalid_csv_path)
  end
  
  describe '#detect_format' do
    it 'returns true for valid Phantom Buster CSV' do
      service = described_class.new(valid_csv_path)
      expect(service.detect_format).to be true
    end
    
    it 'returns false for invalid CSV format' do
      service = described_class.new(invalid_csv_path)
      expect(service.detect_format).to be false
    end
    
    it 'returns false for non-existent file' do
      service = described_class.new('non_existent.csv')
      expect(service.detect_format).to be false
    end
  end
  
  describe '#preview' do
    it 'returns preview of mapped data' do
      service = described_class.new(valid_csv_path)
      preview = service.preview(2)
      
      expect(preview.count).to eq(2)
      expect(preview.first).to include(
        name: 'Test User One',
        first_name: 'Test',
        last_name: 'User One',
        company_name: 'Test Company',
        title: 'Software Engineer',
        profile_url: 'https://www.linkedin.com/in/test-user-1',
        is_premium: true,
        is_open_link: false
      )
    end
    
    it 'returns empty array for invalid file' do
      service = described_class.new(invalid_csv_path)
      expect(service.preview).to eq([])
    end
  end
  
  describe '#import' do
    context 'with valid CSV' do
      let(:service) { described_class.new(valid_csv_path) }
      
      it 'imports all records successfully' do
        expect { 
          result = service.import
          expect(result).to be true
        }.to change(Person, :count).by(2)
        
        expect(service.import_results[:total]).to eq(2)
        expect(service.import_results[:successful]).to eq(2)
        expect(service.import_results[:failed]).to eq(0)
      end
      
      it 'maps all fields correctly' do
        service.import
        
        person = Person.find_by(profile_url: 'https://www.linkedin.com/in/test-user-1')
        expect(person).to have_attributes(
          name: 'Test User One',
          first_name: 'Test',
          last_name: 'User One',
          company_name: 'Test Company',
          title: 'Software Engineer',
          bio: 'Test bio',
          location: 'Oslo, Norway',
          company_location: 'Oslo, Norway',
          industry: 'Technology',
          duration_in_role: '2 years',
          duration_in_company: '3 years',
          past_experience_company_name: 'Previous Company',
          past_experience_company_title: 'Senior Developer',
          shared_connections_count: 50,
          vmid: 'TEST123',
          is_premium: true,
          is_open_link: false,
          source: 'phantom_buster'
        )
      end
      
      it 'sets import_tag' do
        service.import(import_tag: 'test_import_123')
        
        people = Person.where(import_tag: 'test_import_123')
        expect(people.count).to eq(2)
      end
    end
    
    context 'with duplicate records' do
      let(:service) { described_class.new(valid_csv_path) }
      
      before do
        Person.create!(
          name: 'Existing User',
          profile_url: 'https://www.linkedin.com/in/test-user-1',
          email: 'existing@example.com'
        )
      end
      
      it 'skips duplicates by default' do
        expect { service.import }.to change(Person, :count).by(1)
        
        expect(service.import_results[:duplicates]).to eq(1)
        expect(service.import_results[:successful]).to eq(1)
      end
      
      it 'updates duplicates when specified' do
        service.import(duplicate_strategy: :update)
        
        person = Person.find_by(profile_url: 'https://www.linkedin.com/in/test-user-1')
        expect(person.name).to eq('Test User One') # Updated from 'Existing User'
        expect(person.company_name).to eq('Test Company')
      end
      
      it 'creates new records when specified' do
        expect { 
          service.import(duplicate_strategy: :create_new) 
        }.to change(Person, :count).by(2)
        
        # Should have 3 total: 1 existing + 2 new
        expect(Person.count).to eq(3)
      end
    end
    
    context 'with invalid CSV' do
      let(:service) { described_class.new(invalid_csv_path) }
      
      it 'returns false and sets errors' do
        expect(service.import).to be false
        expect(service.errors).to include(/does not match Phantom Buster CSV format/)
      end
      
      it 'does not create any records' do
        expect { service.import }.not_to change(Person, :count)
      end
    end
    
    context 'with malformed data' do
      let(:malformed_csv_path) { Rails.root.join('tmp', 'malformed.csv') }
      let(:service) { described_class.new(malformed_csv_path) }
      
      before do
        content = valid_csv_content + 
          '"https://www.linkedin.com/in/bad-user",,,,Bad Company,,,,,,,,,,,,,,,,,,,,,,,,' # Missing required fields
        File.write(malformed_csv_path, content)
      end
      
      after do
        File.delete(malformed_csv_path) if File.exist?(malformed_csv_path)
      end
      
      it 'continues processing after errors' do
        service.import
        
        expect(service.import_results[:successful]).to eq(2)
        expect(service.import_results[:failed]).to eq(1)
        expect(service.import_results[:errors].count).to eq(1)
      end
    end
  end
  
  describe 'name extraction' do
    let(:service) { described_class.new(valid_csv_path) }
    
    it 'extracts first and last names from full name when not provided' do
      # Modify CSV to have fullName but no firstName/lastName
      content = valid_csv_content.gsub('Test,User One', ',')
      File.write(valid_csv_path, content)
      
      service.import
      
      person = Person.find_by(name: 'Test User One')
      expect(person.first_name).to eq('Test')
      expect(person.last_name).to eq('User One')
    end
  end
  
  describe 'LinkedIn URL normalization' do
    let(:service) { described_class.new(valid_csv_path) }
    
    it 'removes tracking parameters from URLs' do
      content = valid_csv_content.gsub(
        'https://www.linkedin.com/in/test-user-1',
        'https://www.linkedin.com/in/test-user-1?utm_source=test&tracking=123'
      )
      File.write(valid_csv_path, content)
      
      service.import
      
      person = Person.find_by(vmid: 'TEST123')
      expect(person.profile_url).to eq('https://www.linkedin.com/in/test-user-1')
    end
  end
end