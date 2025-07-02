# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "LinkedIn Discovery Queue Integration", type: :request do
  let(:admin_user) { create(:user, email: "admin@example.com") }
  let(:company) { create(:company, linkedin_ai_url: nil, company_name: "Test Company") }

  before do
    # Enable service
    ServiceConfiguration.find_or_create_by(service_name: "company_linkedin_discovery").update(active: true)

    # Configure Sidekiq for testing
    Sidekiq::Testing.fake!
    CompanyLinkedinDiscoveryWorker.clear
  end

  after do
    Sidekiq::Testing.inline!
  end

  describe "End-to-end queueing flow" do
    it "successfully queues a job from controller to Sidekiq" do
      # Sign in as admin
      sign_in admin_user

      # Make request to queue the company
      post "/companies/#{company.id}/queue_single_linkedin_discovery"

      # Verify response
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["success"]).to be true

      # Verify job in queue
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(1)

      job = CompanyLinkedinDiscoveryWorker.jobs.first
      expect(job["args"]).to eq([ company.id ])
      expect(job["queue"]).to eq("company_linkedin_discovery")
      expect(job["class"]).to eq("CompanyLinkedinDiscoveryWorker")
    end

    it "creates audit log and queues job atomically" do
      sign_in admin_user

      expect {
        post "/companies/#{company.id}/queue_single_linkedin_discovery"
      }.to change { ServiceAuditLog.count }.by(1)
        .and change { CompanyLinkedinDiscoveryWorker.jobs.size }.by(1)

      # Verify audit log
      audit_log = ServiceAuditLog.last
      expect(audit_log.auditable).to eq(company)
      expect(audit_log.service_name).to eq("company_linkedin_discovery")
      expect(audit_log.status).to eq("pending")
    end
  end

  describe "Queue processing with real worker" do
    let(:service_double) { instance_double(CompanyLinkedinDiscoveryService) }
    let(:success_result) { OpenStruct.new(success?: true, error: nil, data: {}) }

    before do
      allow(CompanyLinkedinDiscoveryService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:perform).and_return(success_result)
    end

    it "processes queued jobs when worker runs" do
      sign_in admin_user

      # Queue the job
      post "/companies/#{company.id}/queue_single_linkedin_discovery"
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(1)

      # Process the queue
      expect {
        CompanyLinkedinDiscoveryWorker.drain
      }.to change { CompanyLinkedinDiscoveryWorker.jobs.size }.from(1).to(0)

      # Verify service was called
      expect(CompanyLinkedinDiscoveryService).to have_received(:new).with(company_id: company.id)
      expect(service_double).to have_received(:perform)
    end
  end

  describe "Bulk queueing flow" do
    before do
      # Create multiple companies needing LinkedIn discovery
      10.times do |i|
        create(:company,
          registration_number: "NO#{999000 + i}",
          company_name: "Test Company #{i}",
          organization_form_code: "BA",
          operating_revenue: 15_000_000,
          linkedin_ai_url: nil,
          source_country: "NO"
        )
      end
    end

    it "queues multiple companies in bulk" do
      sign_in admin_user

      post "/companies/queue_linkedin_discovery", params: { count: 5 }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["queued_count"]).to eq(5)

      # Verify all jobs are in the correct queue
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(5)

      CompanyLinkedinDiscoveryWorker.jobs.each do |job|
        expect(job["queue"]).to eq("company_linkedin_discovery")
        expect(job["class"]).to eq("CompanyLinkedinDiscoveryWorker")
      end

      # Verify unique company IDs
      queued_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |j| j["args"].first }
      expect(queued_ids.uniq.size).to eq(5)
    end
  end

  describe "Error handling and recovery" do
    it "handles service disable gracefully" do
      sign_in admin_user

      # Disable service
      ServiceConfiguration.find_by(service_name: "company_linkedin_discovery").update(active: false)

      post "/companies/#{company.id}/queue_single_linkedin_discovery"

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["success"]).to be false
      expect(json_response["message"]).to eq("LinkedIn discovery service is disabled")

      # No job should be queued
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(0)
    end

    it "handles non-existent company" do
      sign_in admin_user

      post "/companies/999999/queue_single_linkedin_discovery"

      # In request specs, Rails rescues RecordNotFound and returns 404
      expect(response).to have_http_status(:not_found)
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(0)
    end
  end

  describe "Queue stats verification" do
    it "provides accurate queue statistics" do
      sign_in admin_user

      # Queue some jobs
      3.times do |i|
        company = create(:company, linkedin_ai_url: nil)
        post "/companies/#{company.id}/queue_single_linkedin_discovery"
      end

      # Get queue stats
      queue_stats = Sidekiq::Queue.new("company_linkedin_discovery")

      # In test mode, we need to check the jobs array
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(3)
    end
  end

  describe "Cache invalidation" do
    it "invalidates service stats cache when queueing" do
      sign_in admin_user

      # Pre-populate cache
      Rails.cache.write("service_stats_data", "cached_data")

      post "/companies/#{company.id}/queue_single_linkedin_discovery"

      # Cache should be cleared
      expect(Rails.cache.read("service_stats_data")).to be_nil
    end
  end
end
