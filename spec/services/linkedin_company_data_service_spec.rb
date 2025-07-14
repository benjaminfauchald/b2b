# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LinkedinCompanyDataService, type: :service do
  let(:service_name) { 'linkedin_company_data' }
  let(:mock_extractor) { instance_double(LinkedinCompanyExtractor) }
  let(:sample_company_data) do
    {
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
      entity_urn: 'urn:li:fs_normalized_company:1035',
      extracted_at: Time.current
    }
  end

  before do
    # Set up test environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('LINKEDIN_EMAIL').and_return('test@example.com')
    allow(ENV).to receive(:[]).with('LINKEDIN_PASSWORD').and_return('password123')
    allow(ENV).to receive(:[]).with('LINKEDIN_COOKIE_LI_AT').and_return(nil)
    allow(ENV).to receive(:[]).with('LINKEDIN_COOKIE_JSESSIONID').and_return(nil)

    # Mock the extractor
    allow(LinkedinCompanyExtractor).to receive(:new).and_return(mock_extractor)
    allow(mock_extractor).to receive(:numeric_id?).and_return(true)
    allow(mock_extractor).to receive(:get_company_data).and_return(sample_company_data)
    allow(mock_extractor).to receive(:extract_company_id_from_url).and_return('microsoft')
    allow(mock_extractor).to receive(:get_company_id_from_slug).and_return('1035')

    # Create service configuration
    ServiceConfiguration.create!(
      service_name: service_name,
      active: true,
      configuration_data: { rate_limit_per_hour: 100 },
      description: 'Test LinkedIn Company Data Service'
    )
  end

  describe '#initialize' do
    it 'initializes with company_identifier' do
      service = described_class.new(company_identifier: 'microsoft')
      expect(service.company_identifier).to eq('microsoft')
    end

    it 'initializes with linkedin_url' do
      service = described_class.new(linkedin_url: 'https://www.linkedin.com/company/microsoft')
      expect(service.instance_variable_get(:@linkedin_url)).to eq('https://www.linkedin.com/company/microsoft')
    end

    it 'raises error when neither company_identifier nor linkedin_url is provided' do
      expect {
        described_class.new
      }.to raise_error(ArgumentError, 'Either company_identifier or linkedin_url must be provided')
    end

    it 'initializes the extractor with environment variables' do
      expect(LinkedinCompanyExtractor).to receive(:new).with(
        linkedin_email: 'test@example.com',
        linkedin_password: 'password123',
        li_at_cookie: nil,
        jsessionid_cookie: nil
      )

      described_class.new(company_identifier: 'microsoft')
    end
  end

  describe '#perform' do
    context 'when service is active' do
      it 'successfully extracts company data from identifier' do
        service = described_class.new(company_identifier: 'microsoft')
        result = service.perform

        expect(result[:success]).to be true
        expect(result[:data]).to eq(sample_company_data)
        expect(result[:service]).to eq(service_name)
      end

      it 'successfully extracts company data from LinkedIn URL' do
        service = described_class.new(linkedin_url: 'https://www.linkedin.com/company/microsoft')
        result = service.perform

        expect(result[:success]).to be true
        expect(result[:data]).to eq(sample_company_data)
      end

      it 'handles invalid LinkedIn URL' do
        allow(mock_extractor).to receive(:extract_company_id_from_url).and_return(nil)
        service = described_class.new(linkedin_url: 'https://invalid-url.com')
        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid LinkedIn URL format')
      end

      it 'handles company not found' do
        allow(mock_extractor).to receive(:get_company_data).and_return(nil)
        service = described_class.new(company_identifier: 'nonexistent')
        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Company not found')
      end

      it 'handles authentication errors' do
        allow(mock_extractor).to receive(:get_company_data).and_raise(
          LinkedinCompanyExtractor::AuthenticationError, 'Invalid credentials'
        )
        service = described_class.new(company_identifier: 'microsoft')
        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Authentication failed: Invalid credentials')
      end

      it 'handles rate limit errors' do
        allow(mock_extractor).to receive(:get_company_data).and_raise(
          LinkedinCompanyExtractor::RateLimitError, 'Rate limit exceeded'
        )
        service = described_class.new(company_identifier: 'microsoft')
        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Rate limit exceeded: Rate limit exceeded')
      end

      it 'handles unexpected errors' do
        allow(mock_extractor).to receive(:get_company_data).and_raise(
          StandardError, 'Unexpected error'
        )
        service = described_class.new(company_identifier: 'microsoft')
        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Unexpected error: Unexpected error')
      end
    end

    context 'when service is disabled' do
      before do
        ServiceConfiguration.find_by(service_name: service_name).update!(active: false)
      end

      it 'returns error when service is disabled' do
        service = described_class.new(company_identifier: 'microsoft')
        result = service.perform

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Service is disabled')
      end
    end
  end

  describe 'class methods' do
    describe '.extract_from_url' do
      it 'extracts company data from LinkedIn URL' do
        result = described_class.extract_from_url('https://www.linkedin.com/company/microsoft')

        expect(result[:success]).to be true
        expect(result[:data]).to eq(sample_company_data)
      end
    end

    describe '.extract_from_id' do
      it 'extracts company data from company ID' do
        result = described_class.extract_from_id('microsoft')

        expect(result[:success]).to be true
        expect(result[:data]).to eq(sample_company_data)
      end
    end

    describe '.extract_from_slug' do
      it 'extracts company data from company slug' do
        result = described_class.extract_from_slug('microsoft')

        expect(result[:success]).to be true
        expect(result[:data]).to eq(sample_company_data)
      end
    end

    describe '.get_company_name' do
      it 'returns company name from successful extraction' do
        result = described_class.get_company_name('microsoft')

        expect(result).to eq('Microsoft')
      end

      it 'returns nil for failed extraction' do
        allow(mock_extractor).to receive(:get_company_data).and_return(nil)
        result = described_class.get_company_name('nonexistent')

        expect(result).to be_nil
      end
    end

    describe '.slug_to_id' do
      it 'converts company slug to numeric ID' do
        result = described_class.slug_to_id('microsoft')

        expect(result).to eq('1035')
      end
    end

    describe '.id_to_slug' do
      it 'converts numeric ID to company slug' do
        result = described_class.id_to_slug('1035')

        expect(result).to eq('microsoft')
      end

      it 'returns nil for failed extraction' do
        allow(mock_extractor).to receive(:get_company_data).and_return(nil)
        result = described_class.id_to_slug('nonexistent')

        expect(result).to be_nil
      end
    end
  end

  describe 'audit logging' do
    it 'creates audit log entry for successful extraction' do
      service = described_class.new(company_identifier: 'microsoft')
      
      expect {
        service.perform
      }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.service_name).to eq(service_name)
      expect(audit_log.operation_type).to eq('extract')
      expect(audit_log.status).to eq('success')
      expect(audit_log.metadata['company_name']).to eq('Microsoft')
    end

    it 'creates audit log entry for failed extraction' do
      allow(mock_extractor).to receive(:get_company_data).and_return(nil)
      service = described_class.new(company_identifier: 'nonexistent')
      
      expect {
        service.perform
      }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.service_name).to eq(service_name)
      expect(audit_log.status).to eq('failed')
      expect(audit_log.metadata['error']).to eq('company_not_found')
    end
  end

  describe 'SCT compliance' do
    it 'implements required SCT methods' do
      service = described_class.new(company_identifier: 'microsoft')

      expect(service).to respond_to(:perform)
      expect(service).to respond_to(:service_active?)
      expect(service).to respond_to(:success_result)
      expect(service).to respond_to(:error_result)
    end

    it 'uses service configuration' do
      service = described_class.new(company_identifier: 'microsoft')
      expect(service.configuration).to be_present
      expect(service.configuration.service_name).to eq(service_name)
    end
  end

  describe '.ensure_configuration!' do
    it 'creates service configuration if it does not exist' do
      ServiceConfiguration.where(service_name: service_name).destroy_all
      
      config = described_class.ensure_configuration!
      
      expect(config).to be_persisted
      expect(config.service_name).to eq(service_name)
      expect(config.active).to be true
    end

    it 'finds existing service configuration' do
      existing_config = ServiceConfiguration.find_by(service_name: service_name)
      
      config = described_class.ensure_configuration!
      
      expect(config).to eq(existing_config)
    end
  end
end