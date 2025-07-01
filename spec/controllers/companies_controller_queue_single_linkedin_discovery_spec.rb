# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe CompaniesController, type: :controller do
  describe "POST #queue_single_linkedin_discovery" do
    let(:admin_user) { create(:user, email: "admin@example.com") }
    let(:company) { create(:company, linkedin_ai_url: nil) }

    before do
      sign_in admin_user
      # Enable LinkedIn discovery service
      ServiceConfiguration.find_or_create_by(service_name: "company_linkedin_discovery").update(active: true)
      # Clear any existing jobs
      Sidekiq::Testing.fake!
      CompanyLinkedinDiscoveryWorker.clear
    end

    after do
      Sidekiq::Testing.inline!
    end

    context "when service is enabled and company exists" do
      it "successfully queues the company for LinkedIn discovery" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("Company queued for LinkedIn discovery")
        expect(json_response["company_id"]).to eq(company.id)
        expect(json_response["service"]).to eq("linkedin_discovery")
        expect(json_response["worker"]).to eq("CompanyLinkedinDiscoveryWorker")
        expect(json_response["job_id"]).to be_present
        expect(json_response["audit_log_id"]).to be_present
      end

      it "adds exactly one job to the Sidekiq queue" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.to change { CompanyLinkedinDiscoveryWorker.jobs.size }.by(1)
      end

      it "queues the job with the correct company ID" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        job = CompanyLinkedinDiscoveryWorker.jobs.last
        expect(job["args"]).to eq([company.id])
      end

      it "queues the job to the correct queue" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        job = CompanyLinkedinDiscoveryWorker.jobs.last
        expect(job["queue"]).to eq("company_linkedin_discovery")
      end

      it "creates a service audit log entry" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.to change { ServiceAuditLog.count }.by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.auditable).to eq(company)
        expect(audit_log.service_name).to eq("company_linkedin_discovery")
        expect(audit_log.operation_type).to eq("queue_individual")
        expect(audit_log.status).to eq("pending")
        expect(audit_log.table_name).to eq("companies")
        expect(audit_log.record_id).to eq(company.id.to_s)
        expect(audit_log.columns_affected).to eq(["linkedin_url"])
        expect(audit_log.metadata["action"]).to eq("manual_queue")
        expect(audit_log.metadata["user_id"]).to eq(admin_user.id)
        expect(audit_log.metadata["timestamp"]).to be_present
      end

      it "invalidates the service stats cache" do
        expect(Rails.cache).to receive(:delete).with("service_stats_data")
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
      end

      it "returns the job ID from Sidekiq" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        json_response = JSON.parse(response.body)
        job_id = json_response["job_id"]

        # Verify the job_id matches what's in the queue
        job = CompanyLinkedinDiscoveryWorker.jobs.find { |j| j["jid"] == job_id }
        expect(job).to be_present
      end
    end

    context "when service is disabled" do
      before do
        ServiceConfiguration.find_by(service_name: "company_linkedin_discovery").update(active: false)
      end

      it "returns an error and does not queue the job" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.not_to change { CompanyLinkedinDiscoveryWorker.jobs.size }

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to eq("LinkedIn discovery service is disabled")
      end

      it "does not create an audit log" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.not_to change { ServiceAuditLog.count }
      end
    end

    context "when company does not exist" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: 999999 }, format: :json
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "does not queue any job" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: 999999 }, format: :json rescue nil
        }.not_to change { CompanyLinkedinDiscoveryWorker.jobs.size }
      end
    end

    context "when there's an error queueing the job" do
      before do
        allow(CompanyLinkedinDiscoveryWorker).to receive(:perform_async).and_raise(StandardError, "Queue error")
      end

      it "returns an error response" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be false
        expect(json_response["message"]).to include("Failed to queue company for LinkedIn discovery: Queue error")
      end

      it "still creates an audit log (before the error)" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.to change { ServiceAuditLog.count }.by(1)
      end
    end

    context "when not authenticated" do
      before do
        sign_out admin_user
      end

      it "returns unauthorized status" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "does not queue any job" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.not_to change { CompanyLinkedinDiscoveryWorker.jobs.size }
      end
    end

    context "when authenticated as non-admin user" do
      let(:regular_user) { create(:user, email: "user@example.com") }

      before do
        sign_out admin_user
        sign_in regular_user
      end

      it "allows access (no admin restriction currently)" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        expect(response).to have_http_status(:ok)
      end

      it "successfully queues the job" do
        expect {
          post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
        }.to change { CompanyLinkedinDiscoveryWorker.jobs.size }.by(1)
      end
    end

    context "with multiple rapid requests" do
      it "queues multiple jobs for the same company" do
        expect {
          3.times do
            post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json
          end
        }.to change { CompanyLinkedinDiscoveryWorker.jobs.size }.by(3)

        # All jobs should have the same company ID
        company_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |job| job["args"].first }
        expect(company_ids).to all(eq(company.id))
      end
    end

    context "Sidekiq job details verification" do
      it "queues job with correct class name" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        job = CompanyLinkedinDiscoveryWorker.jobs.last
        expect(job["class"]).to eq("CompanyLinkedinDiscoveryWorker")
      end

      it "queues job with retry enabled" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        job = CompanyLinkedinDiscoveryWorker.jobs.last
        expect(job["retry"]).to eq(3)  # Sidekiq stores retry count as integer
      end

      it "includes job metadata" do
        post :queue_single_linkedin_discovery, params: { id: company.id }, format: :json

        job = CompanyLinkedinDiscoveryWorker.jobs.last
        expect(job["jid"]).to be_present
        expect(job["created_at"]).to be_present
        expect(job["enqueued_at"]).to be_present
      end
    end
  end
end