require 'rails_helper'

RSpec.describe Company, type: :model do
  describe "Profile Extraction Scopes" do
    let!(:company_with_manual_linkedin) do
      create(:company,
        linkedin_url: "https://linkedin.com/company/manual-company",
        linkedin_ai_url: nil,
        linkedin_ai_confidence: nil
      )
    end

    let!(:company_with_high_confidence_ai) do
      create(:company,
        linkedin_url: nil,
        linkedin_ai_url: "https://linkedin.com/company/ai-company",
        linkedin_ai_confidence: 90
      )
    end

    let!(:company_with_low_confidence_ai) do
      create(:company,
        linkedin_url: nil,
        linkedin_ai_url: "https://linkedin.com/company/low-confidence",
        linkedin_ai_confidence: 70
      )
    end

    let!(:company_with_both_urls) do
      create(:company,
        linkedin_url: "https://linkedin.com/company/manual-preferred",
        linkedin_ai_url: "https://linkedin.com/company/ai-backup",
        linkedin_ai_confidence: 85
      )
    end

    let!(:company_with_no_linkedin) do
      create(:company,
        linkedin_url: nil,
        linkedin_ai_url: nil,
        linkedin_ai_confidence: nil
      )
    end

    describe '.profile_extraction_candidates' do
      it 'includes companies with manual LinkedIn URLs' do
        expect(Company.profile_extraction_candidates).to include(company_with_manual_linkedin)
      end

      it 'includes companies with high confidence AI URLs (>= 80%)' do
        expect(Company.profile_extraction_candidates).to include(company_with_high_confidence_ai)
      end

      it 'excludes companies with low confidence AI URLs (< 80%)' do
        expect(Company.profile_extraction_candidates).not_to include(company_with_low_confidence_ai)
      end

      it 'includes companies with both manual and AI URLs' do
        expect(Company.profile_extraction_candidates).to include(company_with_both_urls)
      end

      it 'excludes companies with no LinkedIn URLs' do
        expect(Company.profile_extraction_candidates).not_to include(company_with_no_linkedin)
      end

      it 'orders by operating revenue descending' do
        company_with_manual_linkedin.update(operating_revenue: 1_000_000)
        company_with_high_confidence_ai.update(operating_revenue: 5_000_000)

        candidates = Company.profile_extraction_candidates
        revenues = candidates.pluck(:operating_revenue).compact
        expect(revenues).to eq(revenues.sort.reverse)
      end
    end

    describe '.needing_profile_extraction' do
      let!(:service_config) do
        create(:service_configuration,
          service_name: "person_profile_extraction",
          active: true,
          refresh_interval_hours: 24
        )
      end

      context 'when no previous successful runs exist' do
        it 'includes all profile extraction candidates' do
          candidates = Company.profile_extraction_candidates
          needing = Company.needing_profile_extraction

          expect(needing).to include(company_with_manual_linkedin)
          expect(needing).to include(company_with_high_confidence_ai)
          expect(needing).to include(company_with_both_urls)
          expect(needing).not_to include(company_with_low_confidence_ai)
          expect(needing).not_to include(company_with_no_linkedin)
        end
      end

      context 'when recent successful runs exist' do
        before do
          create(:service_audit_log,
            auditable: company_with_manual_linkedin,
            service_name: "person_profile_extraction",
            status: "success",
            completed_at: 1.hour.ago
          )
        end

        it 'excludes companies with recent successful runs' do
          needing = Company.needing_profile_extraction
          expect(needing).not_to include(company_with_manual_linkedin)
          expect(needing).to include(company_with_high_confidence_ai)
        end
      end

      context 'when old successful runs exist' do
        before do
          create(:service_audit_log,
            auditable: company_with_manual_linkedin,
            service_name: "person_profile_extraction",
            status: "success",
            completed_at: 48.hours.ago
          )
        end

        it 'includes companies with stale successful runs' do
          needing = Company.needing_profile_extraction
          expect(needing).to include(company_with_manual_linkedin)
        end
      end
    end

    describe '.profile_extraction_potential' do
      it 'returns same results as profile_extraction_candidates' do
        expect(Company.profile_extraction_potential.to_a).to eq(Company.profile_extraction_candidates.to_a)
      end
    end
  end

  describe "Instance Methods" do
    describe '#best_linkedin_url' do
      it 'prefers manual linkedin_url over AI URL' do
        company = build(:company,
          linkedin_url: "https://linkedin.com/company/manual",
          linkedin_ai_url: "https://linkedin.com/company/ai",
          linkedin_ai_confidence: 95
        )

        expect(company.best_linkedin_url).to eq("https://linkedin.com/company/manual")
      end

      it 'uses AI URL when manual URL is missing and confidence is >= 80' do
        company = build(:company,
          linkedin_url: nil,
          linkedin_ai_url: "https://linkedin.com/company/ai",
          linkedin_ai_confidence: 85
        )

        expect(company.best_linkedin_url).to eq("https://linkedin.com/company/ai")
      end

      it 'returns nil when AI confidence is < 80' do
        company = build(:company,
          linkedin_url: nil,
          linkedin_ai_url: "https://linkedin.com/company/ai",
          linkedin_ai_confidence: 75
        )

        expect(company.best_linkedin_url).to be_nil
      end

      it 'returns nil when no URLs are present' do
        company = build(:company,
          linkedin_url: nil,
          linkedin_ai_url: nil,
          linkedin_ai_confidence: nil
        )

        expect(company.best_linkedin_url).to be_nil
      end

      it 'handles empty string URLs' do
        company = build(:company,
          linkedin_url: "",
          linkedin_ai_url: "",
          linkedin_ai_confidence: 90
        )

        expect(company.best_linkedin_url).to be_nil
      end
    end

    describe '#ready_for_profile_extraction?' do
      it 'returns true when best_linkedin_url is present' do
        company = build(:company,
          linkedin_url: "https://linkedin.com/company/test",
          linkedin_ai_url: nil,
          linkedin_ai_confidence: nil
        )

        expect(company.ready_for_profile_extraction?).to be true
      end

      it 'returns false when best_linkedin_url is nil' do
        company = build(:company,
          linkedin_url: nil,
          linkedin_ai_url: nil,
          linkedin_ai_confidence: nil
        )

        expect(company.ready_for_profile_extraction?).to be false
      end
    end
  end
end
