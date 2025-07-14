# frozen_string_literal: true

require 'rails_helper'
require_relative '../../lib/linkedin_company_extractor'

RSpec.describe LinkedinCompanyExtractor do
  let(:mock_auth_email) { 'test@example.com' }
  let(:mock_auth_password) { 'password123' }
  let(:mock_li_at_cookie) { 'mock_li_at_cookie_value' }
  let(:mock_jsessionid_cookie) { 'mock_jsessionid_cookie_value' }
  
  let(:sample_python_response) do
    {
      success: true,
      data: {
        id: '1035',
        name: 'Microsoft',
        universal_name: 'microsoft',
        description: 'Microsoft Corporation is an American multinational technology company...',
        website: 'https://www.microsoft.com',
        industry: 'Software Development',
        staff_count: 234339,
        follower_count: 234339,
        headquarters: {
          city: 'Redmond',
          country: 'US',
          geographic_area: 'Washington',
          postal_code: '98052',
          line1: '1 Microsoft Way',
          line2: nil
        },
        founded_year: 1975,
        company_type: 'Public Company',
        specialties: ['Cloud Computing', 'Software Development', 'AI'],
        logo_url: 'https://media.licdn.com/dms/image/company-logo.jpg',
        entity_urn: 'urn:li:fs_normalized_company:1035'
      }
    }
  end

  describe '#initialize' do
    context 'with username and password' do
      it 'initializes successfully' do
        extractor = described_class.new(
          linkedin_email: mock_auth_email,
          linkedin_password: mock_auth_password
        )

        expect(extractor.linkedin_email).to eq(mock_auth_email)
        expect(extractor.linkedin_password).to eq(mock_auth_password)
      end
    end

    context 'with cookie authentication' do
      it 'initializes successfully with li_at cookie' do
        extractor = described_class.new(li_at_cookie: mock_li_at_cookie)

        expect(extractor.li_at_cookie).to eq(mock_li_at_cookie)
      end

      it 'initializes successfully with both cookies' do
        extractor = described_class.new(
          li_at_cookie: mock_li_at_cookie,
          jsessionid_cookie: mock_jsessionid_cookie
        )

        expect(extractor.li_at_cookie).to eq(mock_li_at_cookie)
        expect(extractor.jsessionid_cookie).to eq(mock_jsessionid_cookie)
      end
    end

    context 'with no authentication' do
      it 'raises authentication error' do
        expect {
          described_class.new
        }.to raise_error(LinkedinCompanyExtractor::AuthenticationError, 
                        /LinkedIn credentials not configured/)
      end
    end
  end

  describe '#extract_company_id_from_url' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    it 'extracts numeric company ID from LinkedIn URL' do
      url = 'https://www.linkedin.com/company/51649953'
      result = extractor.extract_company_id_from_url(url)

      expect(result).to eq('51649953')
    end

    it 'extracts company slug from LinkedIn URL' do
      url = 'https://www.linkedin.com/company/telenor-group/'
      result = extractor.extract_company_id_from_url(url)

      expect(result).to eq('telenor-group')
    end

    it 'handles URLs without trailing slash' do
      url = 'https://www.linkedin.com/company/microsoft'
      result = extractor.extract_company_id_from_url(url)

      expect(result).to eq('microsoft')
    end

    it 'returns nil for invalid LinkedIn URL' do
      url = 'https://www.linkedin.com/profile/john-doe'
      result = extractor.extract_company_id_from_url(url)

      expect(result).to be_nil
    end

    it 'returns nil for non-LinkedIn URL' do
      url = 'https://www.google.com'
      result = extractor.extract_company_id_from_url(url)

      expect(result).to be_nil
    end

    it 'handles malformed URLs' do
      url = 'not-a-url'
      result = extractor.extract_company_id_from_url(url)

      expect(result).to be_nil
    end

    it 'handles empty or nil URLs' do
      expect(extractor.extract_company_id_from_url('')).to be_nil
      expect(extractor.extract_company_id_from_url(nil)).to be_nil
    end
  end

  describe '#numeric_id?' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    it 'returns true for numeric identifiers' do
      expect(extractor.numeric_id?('1035')).to be true
      expect(extractor.numeric_id?('51649953')).to be true
    end

    it 'returns false for non-numeric identifiers' do
      expect(extractor.numeric_id?('microsoft')).to be false
      expect(extractor.numeric_id?('telenor-group')).to be false
      expect(extractor.numeric_id?('123abc')).to be false
    end

    it 'handles empty or nil identifiers' do
      expect(extractor.numeric_id?('')).to be false
      expect(extractor.numeric_id?(nil)).to be false
    end
  end

  describe '#get_company_data' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    before do
      allow(extractor).to receive(:execute_python_script).and_return(sample_python_response)
    end

    it 'successfully retrieves company data' do
      result = extractor.get_company_data('microsoft')

      expect(result).to be_a(Hash)
      expect(result[:id]).to eq('1035')
      expect(result[:name]).to eq('Microsoft')
      expect(result[:universal_name]).to eq('microsoft')
      expect(result[:industry]).to eq('Software Development')
      expect(result[:staff_count]).to eq(234339)
      expect(result[:extracted_at]).to be_a(Time)
    end

    it 'handles Python script failure' do
      allow(extractor).to receive(:execute_python_script).and_return({
        success: false,
        error: 'Company not found'
      })

      expect {
        extractor.get_company_data('nonexistent')
      }.to raise_error(LinkedinCompanyExtractor::CompanyNotFoundError)
    end

    it 'handles rate limit errors' do
      allow(extractor).to receive(:execute_python_script).and_return({
        success: false,
        error: 'rate limit exceeded'
      })

      expect {
        extractor.get_company_data('microsoft')
      }.to raise_error(LinkedinCompanyExtractor::RateLimitError)
    end

    it 'handles authentication errors' do
      allow(extractor).to receive(:execute_python_script).and_return({
        success: false,
        error: 'authentication failed'
      })

      expect {
        extractor.get_company_data('microsoft')
      }.to raise_error(LinkedinCompanyExtractor::AuthenticationError)
    end

    it 'returns nil for empty company identifier' do
      result = extractor.get_company_data('')
      expect(result).to be_nil

      result = extractor.get_company_data(nil)
      expect(result).to be_nil
    end
  end

  describe '#extract_company_name_from_url' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    before do
      allow(extractor).to receive(:get_company_data).and_return(sample_python_response[:data])
    end

    it 'extracts company name from LinkedIn URL' do
      url = 'https://www.linkedin.com/company/microsoft'
      result = extractor.extract_company_name_from_url(url)

      expect(result).to eq('Microsoft')
    end

    it 'returns nil for invalid URL' do
      url = 'https://invalid-url.com'
      result = extractor.extract_company_name_from_url(url)

      expect(result).to be_nil
    end
  end

  describe '#get_company_id_from_slug' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    before do
      allow(extractor).to receive(:get_company_data).and_return(sample_python_response[:data])
    end

    it 'returns company ID from slug' do
      result = extractor.get_company_id_from_slug('microsoft')

      expect(result).to eq('1035')
    end

    it 'returns nil when company not found' do
      allow(extractor).to receive(:get_company_data).and_return(nil)
      result = extractor.get_company_id_from_slug('nonexistent')

      expect(result).to be_nil
    end
  end

  describe '#get_company_full_data' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    before do
      allow(extractor).to receive(:get_company_data).and_return(sample_python_response[:data])
    end

    it 'handles LinkedIn URL input' do
      url = 'https://www.linkedin.com/company/microsoft'
      result = extractor.get_company_full_data(url)

      expect(result[:name]).to eq('Microsoft')
    end

    it 'handles direct identifier input' do
      result = extractor.get_company_full_data('microsoft')

      expect(result[:name]).to eq('Microsoft')
    end
  end

  describe 'private methods' do
    let(:extractor) { described_class.new(linkedin_email: mock_auth_email, linkedin_password: mock_auth_password) }

    describe '#execute_python_script' do
      it 'calls Python script with correct arguments' do
        allow(extractor).to receive(:create_python_script_if_needed).and_return('/path/to/script.py')
        allow(extractor).to receive(:find_python_executable).and_return('python3')
        allow(extractor).to receive(:execute_command).and_return({
          success: true,
          output: sample_python_response.to_json
        })

        result = extractor.send(:execute_python_script, 'microsoft')

        expect(result[:success]).to be true
        expect(result[:data]).to eq(sample_python_response[:data])
      end

      it 'handles JSON parsing errors' do
        allow(extractor).to receive(:create_python_script_if_needed).and_return('/path/to/script.py')
        allow(extractor).to receive(:find_python_executable).and_return('python3')
        allow(extractor).to receive(:execute_command).and_return({
          success: true,
          output: 'invalid json'
        })

        result = extractor.send(:execute_python_script, 'microsoft')

        expect(result[:success]).to be false
        expect(result[:error]).to include('Failed to parse script output')
      end
    end

    describe '#create_python_script_if_needed' do
      it 'creates Python script if it does not exist' do
        script_path = Rails.root.join('lib', 'linkedin_company_data_extractor.py')
        
        # Remove script if it exists
        File.delete(script_path) if File.exist?(script_path)
        
        result = extractor.send(:create_python_script_if_needed)
        
        expect(File.exist?(result)).to be true
        expect(result).to eq(script_path.to_s)
      end

      it 'returns existing script path if script exists' do
        script_path = Rails.root.join('lib', 'linkedin_company_data_extractor.py')
        
        # Ensure script exists
        extractor.send(:create_python_script_if_needed)
        
        result = extractor.send(:create_python_script_if_needed)
        
        expect(result).to eq(script_path.to_s)
      end
    end

    describe '#handle_api_error' do
      it 'raises RateLimitError for rate limit messages' do
        expect {
          extractor.send(:handle_api_error, 'rate limit exceeded')
        }.to raise_error(LinkedinCompanyExtractor::RateLimitError)
      end

      it 'raises CompanyNotFoundError for not found messages' do
        expect {
          extractor.send(:handle_api_error, 'company not found')
        }.to raise_error(LinkedinCompanyExtractor::CompanyNotFoundError)
      end

      it 'raises AuthenticationError for authentication messages' do
        expect {
          extractor.send(:handle_api_error, 'authentication failed')
        }.to raise_error(LinkedinCompanyExtractor::AuthenticationError)
      end
    end
  end
end