require 'rails_helper'

RSpec.describe LinkedinCompanyLookup, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:linkedin_company_id) }
    
    subject { build(:linkedin_company_lookup) }
    it { should validate_uniqueness_of(:linkedin_company_id).case_insensitive }
    it { should validate_inclusion_of(:confidence_score).in_range(0..100) }
  end

  describe 'associations' do
    it { should belong_to(:company) }
  end

  describe 'scopes' do
    let!(:high_confidence_lookup) { create(:linkedin_company_lookup, confidence_score: 90) }
    let!(:low_confidence_lookup) { create(:linkedin_company_lookup, confidence_score: 70) }
    let!(:stale_lookup) { create(:linkedin_company_lookup, last_verified_at: 10.days.ago) }
    let!(:fresh_lookup) { create(:linkedin_company_lookup, last_verified_at: 1.day.ago) }

    describe '.high_confidence' do
      it 'returns lookups with confidence >= 80' do
        expect(LinkedinCompanyLookup.high_confidence).to include(high_confidence_lookup)
        expect(LinkedinCompanyLookup.high_confidence).not_to include(low_confidence_lookup)
      end
    end

    describe '.needs_refresh' do
      it 'returns lookups older than 7 days' do
        expect(LinkedinCompanyLookup.needs_refresh).to contain_exactly(stale_lookup)
      end
    end

    describe '.by_slug' do
      it 'returns lookups with matching slug' do
        lookup = create(:linkedin_company_lookup, linkedin_slug: 'test-company')
        expect(LinkedinCompanyLookup.by_slug('test-company')).to contain_exactly(lookup)
      end
    end
  end

  describe 'class methods' do
    let!(:lookup) { create(:linkedin_company_lookup, linkedin_company_id: '12345') }

    describe '.find_company_by_linkedin_id' do
      it 'returns company for valid linkedin_company_id' do
        expect(LinkedinCompanyLookup.find_company_by_linkedin_id('12345')).to eq(lookup.company)
      end

      it 'returns nil for invalid linkedin_company_id' do
        expect(LinkedinCompanyLookup.find_company_by_linkedin_id('99999')).to be_nil
      end
    end

    describe '.find_company_by_slug' do
      it 'returns company for valid slug' do
        lookup.update!(linkedin_slug: 'test-slug')
        expect(LinkedinCompanyLookup.find_company_by_slug('test-slug')).to eq(lookup.company)
      end
    end
  end

  describe 'instance methods' do
    let(:lookup) { create(:linkedin_company_lookup, last_verified_at: 10.days.ago) }

    describe '#stale?' do
      it 'returns true for lookups older than 7 days' do
        expect(lookup.stale?).to be true
      end

      it 'returns false for fresh lookups' do
        lookup.update!(last_verified_at: 1.day.ago)
        expect(lookup.stale?).to be false
      end

      it 'returns true for lookups never verified' do
        lookup.update!(last_verified_at: nil)
        expect(lookup.stale?).to be true
      end
    end

    describe '#mark_verified!' do
      it 'updates last_verified_at to current time' do
        freeze_time do
          lookup.mark_verified!
          expect(lookup.last_verified_at).to be_within(1.second).of(Time.current)
        end
      end
    end
  end
end