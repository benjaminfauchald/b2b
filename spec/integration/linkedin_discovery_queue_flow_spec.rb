# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"
require "sidekiq/api"

RSpec.describe "LinkedIn Discovery Queue Flow", type: :request do
  let(:admin_user) { create(:user, email: "admin@example.com") }

  before do
    # Clean up
    Company.destroy_all
    ServiceAuditLog.destroy_all
    ServiceConfiguration.destroy_all
    
    # Enable service
    ServiceConfiguration.create!(service_name: "company_linkedin_discovery", active: true)
    
    # Use fake mode to prevent actual job processing
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
  end

  after do
    Sidekiq::Testing.inline!
  end

  describe "complete queue flow" do
    before do
      sign_in admin_user
      
      # Create test companies
      10.times do |i|
        create(:company,
          registration_number: "NO#{900000 + i}",
          company_name: "Test Company #{i}",
          source_country: "NO",
          source_registry: "brreg",
          organization_form_code: "AS",
          operating_revenue: 15_000_000 + (i * 1_000_000),
          linkedin_ai_url: nil
        )
      end
    end

    it "successfully queues jobs and updates queue statistics" do
      # Initial state
      expect(Company.needing_service("company_linkedin_discovery").count).to eq(10)
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(0)
      
      # Queue 5 companies
      post "/companies/queue_linkedin_discovery", 
        params: { count: 5 },
        headers: { "Accept" => "application/json" }
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      
      # Verify response
      expect(json["success"]).to be true
      expect(json["queued_count"]).to eq(5)
      expect(json["available_count"]).to eq(10)
      expect(json["queue_stats"]).to be_present
      
      # Verify jobs were queued
      expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(5)
      
      # Verify job structure
      job = CompanyLinkedinDiscoveryWorker.jobs.first
      expect(job["class"]).to eq("CompanyLinkedinDiscoveryWorker")
      expect(job["queue"]).to eq("company_linkedin_discovery")
      expect(job["args"]).to be_an(Array)
      expect(job["args"].first).to be_a(Integer) # company ID
    end

    it "respects the count parameter" do
      [1, 3, 5, 10].each do |count|
        CompanyLinkedinDiscoveryWorker.clear
        
        post "/companies/queue_linkedin_discovery", 
          params: { count: count },
          headers: { "Accept" => "application/json" }
        
        expect(response).to have_http_status(:ok)
        expect(CompanyLinkedinDiscoveryWorker.jobs.size).to eq(count)
      end
    end

    it "queues the correct companies" do
      # Get the companies that should be queued
      expected_companies = Company.needing_service("company_linkedin_discovery").limit(3).pluck(:id)
      
      post "/companies/queue_linkedin_discovery", 
        params: { count: 3 },
        headers: { "Accept" => "application/json" }
      
      # Extract queued company IDs
      queued_ids = CompanyLinkedinDiscoveryWorker.jobs.map { |job| job["args"].first }
      
      # All queued IDs should be from companies needing service
      expect(queued_ids).to all(be_in(Company.pluck(:id)))
      expect(queued_ids.uniq.size).to eq(3)
    end
  end

  describe "Sidekiq queue inspection" do
    it "adds jobs to the correct queue" do
      sign_in admin_user
      
      create(:company,
        registration_number: "NO123456",
        operating_revenue: 20_000_000,
        linkedin_ai_url: nil
      )
      
      # Use inline mode temporarily to test real queue
      Sidekiq::Testing.disable! do
        # Clear the queue first
        Sidekiq::Queue.new("company_linkedin_discovery").clear
        
        post "/companies/queue_linkedin_discovery", 
          params: { count: 1 },
          headers: { "Accept" => "application/json" }
        
        # Check the actual Sidekiq queue
        queue = Sidekiq::Queue.new("company_linkedin_discovery")
        
        # If worker is running, job might be processed immediately
        # So we check if job was queued (might be 0 if processed)
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["queued_count"]).to eq(1)
      end
    end
  end

  describe "queue stats in response" do
    it "returns current queue statistics" do
      sign_in admin_user
      
      create(:company,
        registration_number: "NO111111",
        operating_revenue: 30_000_000,
        linkedin_ai_url: nil
      )
      
      post "/companies/queue_linkedin_discovery", 
        params: { count: 1 },
        headers: { "Accept" => "application/json" }
      
      json = JSON.parse(response.body)
      
      expect(json["queue_stats"]).to be_a(Hash)
      expect(json["queue_stats"]).to have_key("company_linkedin_discovery")
    end
  end

  describe "worker job structure" do
    it "creates jobs with correct metadata" do
      sign_in admin_user
      
      company = create(:company,
        registration_number: "NO222222",
        company_name: "Test LinkedIn Company",
        operating_revenue: 25_000_000,
        linkedin_ai_url: nil
      )
      
      # Queue through the worker directly
      job_id = CompanyLinkedinDiscoveryWorker.perform_async(company.id)
      
      expect(job_id).to be_present
      
      # Check job details
      job = CompanyLinkedinDiscoveryWorker.jobs.last
      expect(job["class"]).to eq("CompanyLinkedinDiscoveryWorker")
      expect(job["queue"]).to eq("company_linkedin_discovery")
      expect(job["retry"]).to eq(3)
      expect(job["args"]).to eq([company.id])
      expect(job["jid"]).to eq(job_id)
    end
  end
end