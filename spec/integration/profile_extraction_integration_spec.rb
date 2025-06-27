require 'rails_helper'

RSpec.describe "Profile Extraction Integration", type: :request do
  include Devise::Test::IntegrationHelpers
  let!(:service_config) do
    create(:service_configuration, 
      service_name: "person_profile_extraction", 
      active: true
    )
  end

  let!(:company_with_manual_linkedin) do
    create(:company, 
      company_name: "Manual LinkedIn Company",
      linkedin_url: "https://linkedin.com/company/manual-test",
      linkedin_ai_url: nil,
      linkedin_ai_confidence: nil
    )
  end

  let!(:company_with_ai_linkedin) do
    create(:company,
      company_name: "AI LinkedIn Company", 
      linkedin_url: nil,
      linkedin_ai_url: "https://linkedin.com/company/ai-test",
      linkedin_ai_confidence: 90
    )
  end

  let!(:company_with_low_confidence) do
    create(:company,
      company_name: "Low Confidence Company",
      linkedin_url: nil,
      linkedin_ai_url: "https://linkedin.com/company/low-confidence",
      linkedin_ai_confidence: 70
    )
  end

  # before do
  #   # Create a test user
  #   @user = create(:user, email: "admin@example.com")
  #   sign_in @user
  # end

  describe "GET /people" do
    it "displays the People index with profile extraction service" do
      get people_path
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Profile Extraction")
      expect(response.body).to include("Queue Processing")
    end

    it "shows correct company count for profile extraction" do
      get people_path
      
      # Should show 2 companies ready for processing (manual + high confidence AI)
      expect(response.body).to include("2 companies need processing")
    end
  end

  describe "POST /people/queue_profile_extraction" do
    before do
      # Mock PhantomBuster environment variables
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PHANTOMBUSTER_PHANTOM_ID").and_return("test_phantom_id")
      allow(ENV).to receive(:[]).with("PHANTOMBUSTER_API_KEY").and_return("test_api_key")
    end

    it "queues companies for profile extraction" do
      expect {
        post queue_profile_extraction_people_path, 
             params: { count: 2 },
             headers: { 'Accept' => 'application/json' }
      }.to change { 
        # Check that jobs were queued (we can't easily test the actual job execution)
        ServiceAuditLog.where(
          service_name: "person_profile_extraction",
          auditable_type: "Company"
        ).count
      }

      expect(response).to have_http_status(:success)
      response_json = JSON.parse(response.body)
      expect(response_json["success"]).to be true
      expect(response_json["message"]).to include("Queued 2 companies")
    end

    it "includes both manual and AI LinkedIn companies" do
      # Mock the worker to capture which companies get queued
      queued_companies = []
      allow(PersonProfileExtractionWorker).to receive(:perform_async) do |company_id|
        queued_companies << company_id
      end

      post queue_profile_extraction_people_path, 
           params: { count: 2 },
           headers: { 'Accept' => 'application/json' }

      expect(queued_companies).to include(company_with_manual_linkedin.id)
      expect(queued_companies).to include(company_with_ai_linkedin.id)
      expect(queued_companies).not_to include(company_with_low_confidence.id)
    end

    it "excludes companies with low confidence AI URLs" do
      post queue_profile_extraction_people_path, 
           params: { count: 10 }, # Request more than available
           headers: { 'Accept' => 'application/json' }

      response_json = JSON.parse(response.body)
      expect(response_json["queued_count"]).to eq(2) # Only 2 companies should be queued
    end
  end

  describe "Company scopes" do
    it "correctly identifies companies ready for profile extraction" do
      candidates = Company.profile_extraction_candidates
      
      expect(candidates).to include(company_with_manual_linkedin)
      expect(candidates).to include(company_with_ai_linkedin)
      expect(candidates).not_to include(company_with_low_confidence)
    end

    it "returns correct best LinkedIn URL for each company" do
      expect(company_with_manual_linkedin.best_linkedin_url).to eq("https://linkedin.com/company/manual-test")
      expect(company_with_ai_linkedin.best_linkedin_url).to eq("https://linkedin.com/company/ai-test")
      expect(company_with_low_confidence.best_linkedin_url).to be_nil
    end
  end

  describe "Service statistics" do
    it "calculates correct potential and completion percentages" do
      # Create one successful audit log
      create(:service_audit_log,
        auditable: company_with_manual_linkedin,
        auditable_type: "Company",
        service_name: "person_profile_extraction",
        status: "success"
      )

      get service_stats_people_path, 
          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Profile Extraction Completion")
      expect(response.body).to include("50%") # 1 out of 2 completed
      expect(response.body).to include("1 of 2 companies processed")
    end
  end
end