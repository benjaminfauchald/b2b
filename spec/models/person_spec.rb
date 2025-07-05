require 'rails_helper'

RSpec.describe Person, type: :model do
  describe 'scopes' do
    describe '.imported_with_tag' do
      let!(:person1) { create(:person, import_tag: 'import_test_20241201_120000') }
      let!(:person2) { create(:person, import_tag: 'import_test_20241201_120000') }
      let!(:person3) { create(:person, import_tag: 'import_other_20241201_130000') }
      let!(:person4) { create(:person, import_tag: nil) }

      it 'returns people with the specified import tag' do
        result = Person.imported_with_tag('import_test_20241201_120000')
        expect(result).to contain_exactly(person1, person2)
      end

      it 'returns empty when no people have the tag' do
        result = Person.imported_with_tag('nonexistent_tag')
        expect(result).to be_empty
      end
    end

    describe 'ZeroBounce scopes' do
      let!(:person_with_zb) { create(:person, zerobounce_status: 'valid', zerobounce_quality_score: 8.5) }
      let!(:person_without_zb) { create(:person, zerobounce_status: nil) }
      let!(:zb_valid_person) { create(:person, zerobounce_status: 'valid') }
      let!(:zb_invalid_person) { create(:person, zerobounce_status: 'invalid') }

      describe '.with_zerobounce_data' do
        it 'returns people with zerobounce data' do
          result = Person.with_zerobounce_data
          expect(result).to contain_exactly(person_with_zb, zb_valid_person, zb_invalid_person)
        end
      end

      describe '.without_zerobounce_data' do
        it 'returns people without zerobounce data' do
          result = Person.without_zerobounce_data
          expect(result).to contain_exactly(person_without_zb)
        end
      end

      describe '.zerobounce_valid' do
        it 'returns people with valid zerobounce status' do
          result = Person.zerobounce_valid
          expect(result).to contain_exactly(person_with_zb, zb_valid_person)
        end
      end

      describe '.zerobounce_invalid' do
        it 'returns people with invalid zerobounce status' do
          result = Person.zerobounce_invalid
          expect(result).to contain_exactly(zb_invalid_person)
        end
      end
    end
  end

  describe 'ZeroBounce methods' do
    let(:person) { create(:person, email: 'test@example.com') }

    describe '#has_zerobounce_data?' do
      it 'returns true when zerobounce_status is present' do
        person.update!(zerobounce_status: 'valid')
        expect(person.has_zerobounce_data?).to be true
      end

      it 'returns false when zerobounce_status is nil' do
        person.update!(zerobounce_status: nil)
        expect(person.has_zerobounce_data?).to be false
      end
    end

    describe '#zerobounce_verified?' do
      it 'returns true when zerobounce_status is valid' do
        person.update!(zerobounce_status: 'valid')
        expect(person.zerobounce_verified?).to be true
      end

      it 'returns false when zerobounce_status is not valid' do
        person.update!(zerobounce_status: 'invalid')
        expect(person.zerobounce_verified?).to be false
      end
    end

    describe '#zerobounce_invalid?' do
      it 'returns true when zerobounce_status is invalid' do
        person.update!(zerobounce_status: 'invalid')
        expect(person.zerobounce_invalid?).to be true
      end

      it 'returns false when zerobounce_status is not invalid' do
        person.update!(zerobounce_status: 'valid')
        expect(person.zerobounce_invalid?).to be false
      end
    end

    describe '#verification_systems_agree?' do
      context 'when both systems have data' do
        before do
          person.update!(
            email_verification_status: 'valid',
            zerobounce_status: 'valid'
          )
        end

        it 'returns true when both systems agree on valid' do
          expect(person.verification_systems_agree?).to be true
        end

        it 'returns false when systems disagree' do
          person.update!(zerobounce_status: 'invalid')
          expect(person.verification_systems_agree?).to be false
        end

        it 'maps suspect to catch-all correctly' do
          person.update!(
            email_verification_status: 'suspect',
            zerobounce_status: 'catch-all'
          )
          expect(person.verification_systems_agree?).to be true
        end
      end

      context 'when missing data' do
        it 'returns false when zerobounce data is missing' do
          person.update!(
            email_verification_status: 'valid',
            zerobounce_status: nil
          )
          expect(person.verification_systems_agree?).to be false
        end

        it 'returns false when our verification status is missing' do
          person.update!(
            email_verification_status: nil,
            zerobounce_status: 'valid'
          )
          expect(person.verification_systems_agree?).to be false
        end
      end
    end

    describe '#confidence_score_comparison' do
      context 'when both confidence scores are present' do
        before do
          person.update!(
            email_verification_confidence: 0.8,
            zerobounce_quality_score: 7.5,
            email_verification_status: 'valid',
            zerobounce_status: 'valid'
          )
        end

        it 'returns comparison data' do
          result = person.confidence_score_comparison

          expect(result).to be_a(Hash)
          expect(result[:our_confidence]).to eq(0.8)
          expect(result[:zerobounce_confidence]).to eq(0.75) # 7.5 / 10.0
          expect(result[:difference]).to eq(0.05)
          expect(result[:systems_agree]).to be true
        end

        it 'calculates difference correctly' do
          person.update!(email_verification_confidence: 0.9)
          result = person.confidence_score_comparison

          expect(result[:difference]).to eq(0.15) # |0.9 - 0.75|
        end
      end

      context 'when confidence data is missing' do
        it 'returns nil when zerobounce quality score is missing' do
          person.update!(
            email_verification_confidence: 0.8,
            zerobounce_quality_score: nil
          )
          expect(person.confidence_score_comparison).to be_nil
        end

        it 'returns nil when our confidence is missing' do
          person.update!(
            email_verification_confidence: nil,
            zerobounce_quality_score: 7.5
          )
          expect(person.confidence_score_comparison).to be_nil
        end
      end
    end
  end
end
