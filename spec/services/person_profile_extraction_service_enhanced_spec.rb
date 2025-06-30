require 'rails_helper'

RSpec.describe PersonProfileExtractionService, type: :service do
  before do
    ServiceConfiguration.find_or_create_by(service_name: "person_profile_extraction") do |config|
      config.active = true
    end
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PHANTOMBUSTER_PHANTOM_ID").and_return("test_phantom_id")
    allow(ENV).to receive(:[]).with("PHANTOMBUSTER_API_KEY").and_return("test_api_key")
  end

  describe "Enhanced URL Handling" do
    context "when company has manual LinkedIn URL" do
      let(:company) do
        create(:company,
          linkedin_url: "https://linkedin.com/company/manual-test",
          linkedin_ai_url: "https://linkedin.com/company/ai-test",
          linkedin_ai_confidence: 85
        )
      end

      it "prefers manual LinkedIn URL" do
        expect(company.best_linkedin_url).to eq("https://linkedin.com/company/manual-test")
      end

      it "logs the URL source as manual" do
        service = PersonProfileExtractionService.new(company_id: company.id)

        # Mock PhantomBuster API calls
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, parsed_response: { 'argument' => {} })
        )
        allow(HTTParty).to receive(:post).and_return(
          double(success?: true, parsed_response: { 'containerId' => 'test_container' })
        )

        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(match(/📎 Using manual LinkedIn URL/))

        # Mock the rest of the workflow to avoid actual API calls
        allow(service).to receive(:monitor_phantom_execution).and_return(
          { success: false, error: "Test stopped here" }
        )

        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to include("Test stopped here")
      end
    end

    context "when company has only high-confidence AI LinkedIn URL" do
      let(:company) do
        create(:company,
          linkedin_url: nil,
          linkedin_ai_url: "https://linkedin.com/company/ai-test",
          linkedin_ai_confidence: 90
        )
      end

      it "uses AI LinkedIn URL" do
        expect(company.best_linkedin_url).to eq("https://linkedin.com/company/ai-test")
      end

      it "logs the URL source as AI-discovered with confidence" do
        service = PersonProfileExtractionService.new(company_id: company.id)

        # Mock PhantomBuster API calls
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, parsed_response: { 'argument' => {} })
        )
        allow(HTTParty).to receive(:post).and_return(
          double(success?: true, parsed_response: { 'containerId' => 'test_container' })
        )

        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(match(/📎 Using AI-discovered LinkedIn URL.*90% confidence/))

        # Mock the rest of the workflow to avoid actual API calls
        allow(service).to receive(:monitor_phantom_execution).and_return(
          { success: false, error: "Test stopped here" }
        )

        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to include("Test stopped here")
      end
    end

    context "when company has low-confidence AI LinkedIn URL" do
      let(:company) do
        create(:company,
          linkedin_url: nil,
          linkedin_ai_url: "https://linkedin.com/company/low-confidence",
          linkedin_ai_confidence: 70
        )
      end

      it "returns error for low confidence AI URL" do
        service = PersonProfileExtractionService.new(company_id: company.id)
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to eq("Company has no valid LinkedIn URL")
      end
    end

    context "when company has no LinkedIn URLs" do
      let(:company) do
        create(:company,
          linkedin_url: nil,
          linkedin_ai_url: nil,
          linkedin_ai_confidence: nil
        )
      end

      it "returns error for missing LinkedIn URL" do
        service = PersonProfileExtractionService.new(company_id: company.id)
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to eq("Company has no valid LinkedIn URL")
      end
    end
  end

  describe "Audit Log Metadata Enhancement" do
    let(:company) do
      create(:company,
        linkedin_url: nil,
        linkedin_ai_url: "https://linkedin.com/company/ai-test",
        linkedin_ai_confidence: 85
      )
    end

    it "includes URL source and confidence in audit metadata" do
      service = PersonProfileExtractionService.new(company_id: company.id)

      # Mock PhantomBuster API calls
      allow(HTTParty).to receive(:get).and_return(
        double(success?: true, parsed_response: { 'argument' => {} })
      )
      allow(HTTParty).to receive(:post).and_return(
        double(success?: true, parsed_response: { 'containerId' => 'test_container' })
      )

      # Mock the rest of the workflow
      allow(service).to receive(:monitor_phantom_execution).and_return(
        { success: false, error: "Test stopped here" }
      )

      result = service.call

      # Check that audit log was created with enhanced metadata
      audit_log = ServiceAuditLog.where(
        auditable: company,
        service_name: "person_profile_extraction"
      ).first

      expect(audit_log).to be_present
      expect(audit_log.metadata).to include(
        "container_id" => "test_container",
        "phantom_id" => "test_phantom_id",
        "linkedin_url" => "https://linkedin.com/company/ai-test",
        "url_source" => "AI-discovered",
        "linkedin_ai_confidence" => 85
      )
    end
  end
end
