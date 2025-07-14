require 'rails_helper'

RSpec.describe LinkedinCompanyResolver, type: :service do
  let(:resolver) { described_class.new }

  describe '#resolve' do
    let!(:company) { create(:company, linkedin_company_id: '12345', linkedin_slug: 'test-company') }

    context 'with valid LinkedIn company ID' do
      it 'returns company from lookup table' do
        lookup = create(:linkedin_company_lookup, linkedin_company_id: '12345', company: company)
        
        result = resolver.resolve('12345')
        expect(result).to eq(company)
      end

      it 'returns company from direct company match' do
        result = resolver.resolve('12345')
        expect(result).to eq(company)
      end

      it 'creates lookup entry for direct company match' do
        expect {
          resolver.resolve('12345')
        }.to change(LinkedinCompanyLookup, :count).by(1)

        lookup = LinkedinCompanyLookup.find_by(linkedin_company_id: '12345')
        expect(lookup.company).to eq(company)
        expect(lookup.linkedin_slug).to eq('test-company')
      end

      it 'caches results' do
        Rails.cache.clear
        
        expect(resolver).to receive(:resolve_from_strategies).once.and_return(company)
        
        # First call
        result1 = resolver.resolve('12345')
        # Second call should use cache
        result2 = resolver.resolve('12345')
        
        expect(result1).to eq(company)
        expect(result2).to eq(company)
      end
    end

    context 'with slug conversion' do
      let!(:company_with_slug) { create(:company, linkedin_slug: 'converted-slug') }

      it 'converts ID to slug and finds company' do
        allow(LinkedinCompanyDataService).to receive(:id_to_slug).with('54321').and_return('converted-slug')
        
        result = resolver.resolve('54321')
        expect(result).to eq(company_with_slug)
      end

      it 'creates lookup entry for slug conversion' do
        allow(LinkedinCompanyDataService).to receive(:id_to_slug).with('54321').and_return('converted-slug')
        
        expect {
          resolver.resolve('54321')
        }.to change(LinkedinCompanyLookup, :count).by(1)

        lookup = LinkedinCompanyLookup.find_by(linkedin_company_id: '54321')
        expect(lookup.company).to eq(company_with_slug)
        expect(lookup.linkedin_slug).to eq('converted-slug')
      end
    end

    context 'with invalid LinkedIn company ID' do
      it 'returns nil for non-existent company' do
        result = resolver.resolve('99999')
        expect(result).to be_nil
      end

      it 'returns nil for malformed ID' do
        result = resolver.resolve('abc123')
        expect(result).to be_nil
      end

      it 'returns nil for empty ID' do
        result = resolver.resolve('')
        expect(result).to be_nil
      end
    end

    context 'with fallback matching enabled' do
      let!(:service_config) { create(:service_configuration, service_name: 'linkedin_company_association', settings: { 'enable_fallback_matching' => true }) }
      let!(:company_with_url) { create(:company, linkedin_ai_url: 'https://linkedin.com/company/67890') }

      it 'finds company through fallback URL matching' do
        result = resolver.resolve('67890')
        expect(result).to eq(company_with_url)
      end

      it 'creates lookup entry with lower confidence for fallback match' do
        resolver.resolve('67890')
        
        lookup = LinkedinCompanyLookup.find_by(linkedin_company_id: '67890')
        expect(lookup.company).to eq(company_with_url)
        expect(lookup.confidence_score).to eq(75)
      end
    end

    context 'with stale lookup entries' do
      let!(:stale_lookup) { create(:linkedin_company_lookup, linkedin_company_id: '12345', company: company, last_verified_at: 10.days.ago) }

      it 'marks stale entries as verified' do
        resolver.resolve('12345')
        
        stale_lookup.reload
        expect(stale_lookup.last_verified_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe '#normalize_linkedin_id' do
    it 'removes non-numeric characters' do
      expect(resolver.send(:normalize_linkedin_id, 'abc123def')).to eq('123')
    end

    it 'handles pure numeric strings' do
      expect(resolver.send(:normalize_linkedin_id, '12345')).to eq('12345')
    end

    it 'returns nil for empty result' do
      expect(resolver.send(:normalize_linkedin_id, 'abc')).to be_nil
    end
  end
end