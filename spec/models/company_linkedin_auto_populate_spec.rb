require 'rails_helper'

RSpec.describe Company, type: :model do
  describe 'LinkedIn URL auto-population' do
    let(:company) { create(:company, linkedin_url: nil) }

    context 'when AI confidence is 80% or higher' do
      it 'auto-populates linkedin_url from AI URL' do
        company.update!(
          linkedin_ai_url: 'https://linkedin.com/company/test-company',
          linkedin_ai_confidence: 80
        )

        expect(company.reload.linkedin_url).to eq('https://linkedin.com/company/test-company')
      end

      it 'auto-populates when confidence increases to 80%' do
        company.update!(
          linkedin_ai_url: 'https://linkedin.com/company/test-company',
          linkedin_ai_confidence: 70
        )
        expect(company.linkedin_url).to be_nil

        company.update!(linkedin_ai_confidence: 80)
        expect(company.reload.linkedin_url).to eq('https://linkedin.com/company/test-company')
      end
    end

    context 'when AI confidence is below 80%' do
      it 'does not auto-populate linkedin_url' do
        company.update!(
          linkedin_ai_url: 'https://linkedin.com/company/test-company',
          linkedin_ai_confidence: 79
        )

        expect(company.reload.linkedin_url).to be_nil
      end
    end

    context 'when manual linkedin_url already exists' do
      let(:company) { create(:company, linkedin_url: 'https://linkedin.com/company/manual-url') }

      it 'does not overwrite manual URL even with high confidence AI' do
        company.update!(
          linkedin_ai_url: 'https://linkedin.com/company/ai-url',
          linkedin_ai_confidence: 95
        )

        expect(company.reload.linkedin_url).to eq('https://linkedin.com/company/manual-url')
      end
    end

    context 'when AI URL is updated' do
      it 'updates linkedin_url if confidence is high enough' do
        company.update!(
          linkedin_ai_url: 'https://linkedin.com/company/old-url',
          linkedin_ai_confidence: 85
        )
        expect(company.linkedin_url).to eq('https://linkedin.com/company/old-url')

        company.update!(linkedin_ai_url: 'https://linkedin.com/company/new-url')
        expect(company.reload.linkedin_url).to eq('https://linkedin.com/company/new-url')
      end
    end
  end

  describe '#best_linkedin_url' do
    let(:company) { create(:company) }

    it 'returns manual URL when present' do
      company.update!(
        linkedin_url: 'https://linkedin.com/company/manual',
        linkedin_ai_url: 'https://linkedin.com/company/ai',
        linkedin_ai_confidence: 90
      )

      expect(company.best_linkedin_url).to eq('https://linkedin.com/company/manual')
    end

    it 'returns AI URL when manual is blank and confidence >= 80' do
      company.update!(
        linkedin_url: nil,
        linkedin_ai_url: 'https://linkedin.com/company/ai',
        linkedin_ai_confidence: 80
      )

      expect(company.best_linkedin_url).to eq('https://linkedin.com/company/ai')
    end

    it 'returns nil when manual is blank and confidence < 80' do
      company.update!(
        linkedin_url: nil,
        linkedin_ai_url: 'https://linkedin.com/company/ai',
        linkedin_ai_confidence: 79
      )

      expect(company.best_linkedin_url).to be_nil
    end
  end
end
