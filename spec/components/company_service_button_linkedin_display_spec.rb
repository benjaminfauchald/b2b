# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompanyServiceButtonComponent, type: :component do
  describe "LinkedIn Discovery display" do
    let(:company) { create(:company, operating_revenue: 50_000_000) }
    let(:component) do
      described_class.new(
        company: company,
        service: :linkedin_discovery
      )
    end

    before do
      ServiceConfiguration.find_or_create_by(service_name: "company_linkedin_discovery").update(active: true)
    end

    context "when company has no LinkedIn data" do
      it "shows 'No Data' status" do
        render_inline(component)
        
        expect(page).to have_text("No Data")
        expect(page).to have_button("Fetch LinkedIn")
      end
    end

    context "when company has manual LinkedIn URL only" do
      before do
        company.update!(
          linkedin_url: "https://www.linkedin.com/company/test-company",
          linkedin_last_processed_at: 1.hour.ago
        )
      end

      it "displays the manual URL" do
        render_inline(component)
        
        expect(page).to have_text("Manual")
        expect(page).to have_text("Manual URL:")
        expect(page).to have_link("company/test-company", href: "https://www.linkedin.com/company/test-company")
        expect(page).to have_button("Update LinkedIn")
      end
    end

    context "when company has AI-discovered LinkedIn URL" do
      before do
        company.update!(
          linkedin_ai_url: "https://www.linkedin.com/company/ai-discovered-company",
          linkedin_ai_confidence: 85,
          linkedin_last_processed_at: 2.hours.ago
        )
      end

      it "displays the AI URL with confidence score" do
        render_inline(component)
        
        expect(page).to have_text("AI (85%)")
        expect(page).to have_text("AI URL (Confidence: 85%):")
        expect(page).to have_link("company/ai-discovered-company", href: "https://www.linkedin.com/company/ai-discovered-company")
        expect(page).to have_button("Update LinkedIn")
      end
    end

    context "when company has both manual and AI URLs" do
      before do
        company.update!(
          linkedin_url: "https://www.linkedin.com/company/manual-company",
          linkedin_ai_url: "https://www.linkedin.com/company/ai-company",
          linkedin_ai_confidence: 90,
          linkedin_last_processed_at: 30.minutes.ago
        )
      end

      it "displays both URLs" do
        render_inline(component)
        
        expect(page).to have_text("Manual + AI (90%)")
        expect(page).to have_text("Manual URL:")
        expect(page).to have_link("company/manual-company")
        expect(page).to have_text("AI URL (Confidence: 90%):")
        expect(page).to have_link("company/ai-company")
      end
    end

    context "when company has alternative LinkedIn suggestions" do
      before do
        company.update!(
          linkedin_ai_url: "https://www.linkedin.com/company/main-company",
          linkedin_ai_confidence: 95,
          linkedin_alternatives: [
            {
              "url" => "https://www.linkedin.com/company/alt-company-1",
              "confidence" => 80,
              "title" => "Alternative Company 1"
            },
            {
              "url" => "https://www.linkedin.com/company/alt-company-2",
              "confidence" => 75,
              "title" => "Alternative Company 2"
            }
          ],
          linkedin_last_processed_at: 1.hour.ago
        )
      end

      it "displays alternative suggestions" do
        render_inline(component)
        
        expect(page).to have_text("AI (95%)")
        expect(page).to have_text("Alternative suggestions:")
        expect(page).to have_link("company/alt-company-1", href: "https://www.linkedin.com/company/alt-company-1")
        expect(page).to have_text("(confidence: 80%)")
        expect(page).to have_link("company/alt-company-2", href: "https://www.linkedin.com/company/alt-company-2")
        expect(page).to have_text("(confidence: 75%)")
      end
    end

    context "when company has array of URL strings as alternatives" do
      before do
        company.update!(
          linkedin_ai_url: "https://www.linkedin.com/company/main",
          linkedin_ai_confidence: 90,
          linkedin_alternatives: [
            "https://www.linkedin.com/company/alt1",
            "https://www.linkedin.com/company/alt2"
          ],
          linkedin_last_processed_at: 45.minutes.ago
        )
      end

      it "handles simple URL array format" do
        render_inline(component)
        
        expect(page).to have_text("Alternative suggestions:")
        expect(page).to have_link("company/alt1", href: "https://www.linkedin.com/company/alt1")
        expect(page).to have_link("company/alt2", href: "https://www.linkedin.com/company/alt2")
      end
    end

    context "display timing" do
      before do
        company.update!(
          linkedin_ai_url: "https://www.linkedin.com/company/test",
          linkedin_ai_confidence: 80,
          linkedin_last_processed_at: 3.days.ago
        )
      end

      it "shows when the data was last updated" do
        render_inline(component)
        
        expect(page).to have_text("3 days ago")
      end
    end
  end
end