require 'rails_helper'

RSpec.describe LinkedinCompanySlugService, type: :service do
  let(:service) { described_class.new }

  describe '#perform' do
    let!(:service_config) { create(:service_configuration, service_name: 'linkedin_company_slug_population', active: true) }

    context 'when service is active' do
      let!(:company1) { create(:company, linkedin_ai_url: 'https://no.linkedin.com/company/test-company-1', linkedin_slug: nil) }
      let!(:company2) { create(:company, linkedin_ai_url: 'https://no.linkedin.com/company/test-company-2', linkedin_slug: nil) }

      it 'populates slugs for companies' do
        result = service.perform

        expect(result[:success]).to be true
        expect(result[:data][:processed]).to eq(2)
        expect(result[:data][:successful]).to eq(2)
        expect(result[:data][:errors]).to eq(0)

        company1.reload
        company2.reload
        expect(company1.linkedin_slug).to eq('test-company-1')
        expect(company2.linkedin_slug).to eq('test-company-2')
      end

      it 'handles duplicate slugs gracefully' do
        # Create a company with an existing slug
        create(:company, linkedin_slug: 'test-company-1')

        result = service.perform

        expect(result[:success]).to be true
        expect(result[:data][:processed]).to eq(2)
        expect(result[:data][:successful]).to eq(1)
        expect(result[:data][:errors]).to eq(1)

        company1.reload
        company2.reload
        expect(company1.linkedin_slug).to be_nil  # Skipped due to duplicate
        expect(company2.linkedin_slug).to eq('test-company-2')
      end

      it 'creates lookup entries for successful updates' do
        company1.update!(linkedin_company_id: '12345')

        result = service.perform

        expect(result[:success]).to be true
        lookup = LinkedinCompanyLookup.find_by(linkedin_company_id: '12345')
        expect(lookup).to be_present
        expect(lookup.company).to eq(company1)
        expect(lookup.linkedin_slug).to eq('test-company-1')
      end
    end

    context 'when service is disabled' do
      let!(:service_config) { create(:service_configuration, service_name: 'linkedin_company_slug_population', active: false) }

      it 'returns error result' do
        result = service.perform
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Service is disabled')
      end
    end
  end

  describe '#extract_slug_from_url' do
    it 'extracts slug from Norwegian LinkedIn URLs' do
      url = 'https://no.linkedin.com/company/test-company'
      slug = service.send(:extract_slug_from_url, url)
      expect(slug).to eq('test-company')
    end

    it 'extracts slug from international LinkedIn URLs' do
      url = 'https://www.linkedin.com/company/test-company'
      slug = service.send(:extract_slug_from_url, url)
      expect(slug).to eq('test-company')
    end

    it 'handles URLs with query parameters' do
      url = 'https://www.linkedin.com/company/test-company?param=value'
      slug = service.send(:extract_slug_from_url, url)
      expect(slug).to eq('test-company')
    end

    it 'handles URLs with trailing slashes' do
      url = 'https://www.linkedin.com/company/test-company/'
      slug = service.send(:extract_slug_from_url, url)
      expect(slug).to eq('test-company')
    end

    it 'returns nil for invalid URLs' do
      expect(service.send(:extract_slug_from_url, 'invalid-url')).to be_nil
      expect(service.send(:extract_slug_from_url, nil)).to be_nil
      expect(service.send(:extract_slug_from_url, '')).to be_nil
    end
  end
end