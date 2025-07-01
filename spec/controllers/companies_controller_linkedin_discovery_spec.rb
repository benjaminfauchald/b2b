# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe CompaniesController, type: :controller do
  describe "POST #queue_linkedin_discovery" do
    let(:admin_user) { create(:user, email: "admin@example.com") }

    before do
      sign_in admin_user
      # Clean up any existing data to ensure test isolation
      Company.destroy_all
      ServiceAuditLog.destroy_all
      ServiceConfiguration.destroy_all

      # Enable LinkedIn discovery service
      ServiceConfiguration.find_or_create_by(service_name: "company_linkedin_discovery").update(active: true)
      # Clear any existing jobs
      Sidekiq::Testing.fake!
      CompanyLinkedinDiscoveryWorker.clear
    end

    after do
      Sidekiq::Testing.inline!
    end

    context "when there are companies needing LinkedIn discovery" do
      let!(:companies_needing_service) do
        # Create companies that match linkedin_discovery_potential criteria:
        # - operating_revenue > 10_000_000
        # - NOT excluded org forms (SPF, ENK, FLI, ORKEST, ESEK, DA, GFS, IKJP, PK, TVAM, KIRK, FKF, IKS, KF, KTRF, KS, KOMM, ORGL, SAMD, SÆR, SF, STAT, VASS, VPFO, AS, ASA, ANS)
        # - no linkedin_ai_url
        10.times.map do |i|
          create(:company,
            registration_number: "NO#{999000 + i}",
            company_name: "LinkedIn Test Company #{i}",
            source_country: "NO",
            source_registry: "brreg",
            organization_form_code: "BA", # Valid form for LinkedIn discovery
            operating_revenue: 15_000_000 + (i * 1_000_000),
            linkedin_ai_url: nil,
            linkedin_last_processed_at: nil
          )
        end
      end

      it "successfully queues the requested number of companies" do
        post :queue_linkedin_discovery, params: { count: 5 }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("Queued 5 companies for LinkedIn discovery")
        expect(json_response["queued_count"]).to eq(5)
        expect(json_response["available_count"]).to eq(10)

        # Check that jobs were added to Sidekiq queue
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(5)

        # Verify that queued companies are from our test set
        queued_company_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |job| job["args"].first }
        all_test_company_ids = companies_needing_service.map(&:id)

        # All queued IDs should be from our test companies
        expect(queued_company_ids).to all(be_in(all_test_company_ids))
        # Should queue exactly 5 unique companies
        expect(queued_company_ids.uniq.size).to eq(5)
      end

      it "queues the default number (10) when no count is specified" do
        post :queue_linkedin_discovery, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be true
        expect(json_response["queued_count"]).to eq(10)
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(10)
      end

      it "returns queue statistics in the response" do
        post :queue_linkedin_discovery, params: { count: 3 }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["queue_stats"]).to be_present
        expect(json_response["queue_stats"]).to be_a(Hash)
      end

      it "invalidates the service stats cache" do
        expect(Rails.cache).to receive(:delete).with("service_stats_data")

        post :queue_linkedin_discovery, params: { count: 3 }, format: :json
      end

      context "when requesting more companies than available" do
        it "returns an error with available count" do
          post :queue_linkedin_discovery, params: { count: 20 }, format: :json

          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be false
          expect(json_response["message"]).to include("Only 10 companies need LinkedIn discovery processing")
          expect(json_response["available_count"]).to eq(10)

          # No jobs should be queued
          expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(0)
        end
      end

      context "with country filtering" do
        before do
          # Create companies from different countries
          create(:company,
            registration_number: "SE999999",
            company_name: "Swedish Company",
            source_country: "SE",
            source_registry: "bolagsverket",
            organization_form_code: "AB",
            operating_revenue: 20_000_000,
            linkedin_ai_url: nil
          )

          session[:selected_country] = "NO"
        end

        it "only queues companies from the selected country" do
          post :queue_linkedin_discovery, params: { count: 5 }, format: :json

          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be true
          expect(json_response["queued_count"]).to eq(5)

          # Verify only Norwegian companies were queued
          queued_company_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |job| job["args"].first }
          queued_companies = Company.where(id: queued_company_ids)
          expect(queued_companies.pluck(:source_country).uniq).to eq([ "NO" ])
        end
      end
    end

    context "when no companies need LinkedIn discovery" do
      before do
        # Create companies that don't match criteria (already have linkedin_ai_url)
        create(:company,
          operating_revenue: 20_000_000,
          organization_form_code: "AS",
          linkedin_ai_url: "https://linkedin.com/company/test"
        )
      end

      it "returns an appropriate error message" do
        post :queue_linkedin_discovery, params: { count: 5 }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("No companies need LinkedIn discovery processing at this time")
        expect(json_response["available_count"]).to eq(0)

        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(0)
      end
    end

    context "with invalid parameters" do
      it "returns an error for zero count" do
        post :queue_linkedin_discovery, params: { count: 0 }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("Count must be greater than 0")
      end

      it "returns an error for negative count" do
        post :queue_linkedin_discovery, params: { count: -5 }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("Count must be greater than 0")
      end

      it "returns an error for count exceeding 1000" do
        post :queue_linkedin_discovery, params: { count: 1001 }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("Cannot queue more than 1000 companies at once")
      end
    end

    context "when service is disabled" do
      before do
        ServiceConfiguration.find_by(service_name: "company_linkedin_discovery").update(active: false)
      end

      it "returns an error message" do
        post :queue_linkedin_discovery, params: { count: 5 }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("LinkedIn discovery service is disabled")

        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(0)
      end
    end

    context "when not authenticated" do
      before do
        sign_out admin_user
      end

      it "redirects to login" do
        post :queue_linkedin_discovery, params: { count: 5 }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated as non-admin" do
      let(:regular_user) { create(:user, email: "user@example.com") }

      before do
        sign_out admin_user
        sign_in regular_user
      end

      it "allows access (no admin restriction currently)" do
        post :queue_linkedin_discovery, params: { count: 5 }, format: :json
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        # Should return no companies available since we didn't create any
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("No companies need LinkedIn discovery processing at this time")
      end
    end
  end

  describe "service stats update after queueing" do
    let(:admin_user) { create(:user, email: "admin@example.com") }

    before do
      sign_in admin_user
      # Clean up any existing data
      Company.destroy_all
      ServiceAuditLog.destroy_all
      ServiceConfiguration.destroy_all

      ServiceConfiguration.find_or_create_by(service_name: "company_linkedin_discovery").update(active: true)
      Sidekiq::Testing.fake!
    end

    it "updates the LinkedIn discovery stats after queueing" do
      # Create companies needing service
      5.times do |i|
        create(:company,
          registration_number: "NO#{888000 + i}",
          organization_form_code: "BA",
          operating_revenue: 20_000_000,
          linkedin_ai_url: nil
        )
      end

      # Queue some companies
      post :queue_linkedin_discovery, params: { count: 3 }, format: :json

      # Request service stats
      get :service_stats, format: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("company_linkedin_discovery_stats")
    end
  end
end
