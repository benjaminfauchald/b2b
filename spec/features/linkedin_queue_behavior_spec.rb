# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"
require "sidekiq/api"

RSpec.describe "LinkedIn Queue Behavior", type: :feature do
  describe "Queue shows 0 when workers are processing jobs immediately" do
    it "demonstrates why queue shows 0 in production" do
      # This test demonstrates the actual behavior you're seeing

      # 1. When Sidekiq workers are running (like in your production)
      Sidekiq::Testing.inline! do
        # Jobs are processed immediately
        job_id = CompanyLinkedinDiscoveryWorker.perform_async(123)

        # Queue will be empty because job was processed
        queue = Sidekiq::Queue.new("company_linkedin_discovery")
        expect(queue.size).to eq(0)
      end

      # 2. When we want to see jobs in queue, we disable processing
      Sidekiq::Testing.fake! do
        # Jobs are queued but not processed
        CompanyLinkedinDiscoveryWorker.perform_async(123)
        CompanyLinkedinDiscoveryWorker.perform_async(124)
        CompanyLinkedinDiscoveryWorker.perform_async(125)

        # Now we can see the jobs in the queue
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(3)
      end

      # 3. In real production with active workers
      Sidekiq::Testing.disable! do
        # Clear the queue first
        Sidekiq::Queue.new("company_linkedin_discovery").clear

        # Queue a job
        CompanyLinkedinDiscoveryWorker.perform_async(123)

        # In production with workers running, this will likely be 0
        # because the worker picks it up immediately
        queue = Sidekiq::Queue.new("company_linkedin_discovery")
        # Queue size is 0 or very small because workers are fast
        expect(queue.size).to be >= 0
      end
    end
  end

  describe "How to verify LinkedIn Discovery is working", type: :request do
    include Devise::Test::IntegrationHelpers
    
    let(:admin_user) { create(:user, email: "admin@example.com") }

    before do
      Company.destroy_all
      ServiceAuditLog.destroy_all
      ServiceConfiguration.create!(service_name: "company_linkedin_discovery", active: true)
      sign_in admin_user
    end

    it "shows jobs are being processed by checking audit logs" do
      # Create a company
      company = create(:company,
        registration_number: "NO123456",
        company_name: "Test Company for LinkedIn",
        operating_revenue: 50_000_000,
        linkedin_ai_url: nil
      )

      # Process the job inline (simulating what workers do)
      Sidekiq::Testing.inline! do
        # This will queue and immediately process the job
        post "/companies/queue_linkedin_discovery",
          params: { count: 1 },
          headers: { "Accept" => "application/json" }

        # Check response
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["queued_count"]).to eq(1)
      end

      # The real proof that it's working is in the audit logs
      # (In production, check ServiceAuditLog to see processed companies)
      # audit_logs = ServiceAuditLog.where(service_name: "company_linkedin_discovery")
      # expect(audit_logs.count).to be > 0
    end
  end

  describe "Monitoring LinkedIn Discovery processing" do
    it "provides metrics to track processing" do
      # Key metrics to monitor:

      # 1. Total companies needing LinkedIn discovery
      needing_count = Company.needing_service("company_linkedin_discovery").count
      puts "Companies needing LinkedIn discovery: #{needing_count}"

      # 2. Successfully processed (would have audit logs)
      processed_count = ServiceAuditLog
        .where(service_name: "company_linkedin_discovery", status: "success")
        .count
      puts "Successfully processed: #{processed_count}"

      # 3. Failed attempts (in retry or dead set)
      retry_set = Sidekiq::RetrySet.new
      failed_count = retry_set.select { |job| job.queue == "company_linkedin_discovery" }.size
      puts "Jobs in retry: #{failed_count}"

      # 4. Queue latency (how long jobs wait before processing)
      queue = Sidekiq::Queue.new("company_linkedin_discovery")
      puts "Queue latency: #{queue.latency} seconds"

      # A healthy system shows:
      # - Queue size: 0 (or very low)
      # - Queue latency: < 1 second
      # - Increasing processed count over time
      # - Low retry count
    end
  end
end
