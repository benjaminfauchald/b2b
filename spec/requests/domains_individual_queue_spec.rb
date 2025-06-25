# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Domain Individual Queue Testing', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let(:domain) { create(:domain) }

  before do
    sign_in user
    # Clear Sidekiq jobs before each test
    Sidekiq::Worker.clear_all
  end

  describe 'POST /domains/:id/queue_single_dns' do
    context 'when service is active' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_testing").and_return(true)
      end

      it 'queues the specific domain for DNS testing' do
        expect {
          post queue_single_dns_domain_path(domain)
        }.to change { DomainDnsTestingWorker.jobs.size }.by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["message"]).to eq("Domain queued for DNS testing")
        expect(json["domain_id"]).to eq(domain.id)
        expect(json["service"]).to eq("dns")
      end

      it 'includes job information in response' do
        post queue_single_dns_domain_path(domain)

        json = JSON.parse(response.body)
        expect(json).to have_key("job_id")
        expect(json["worker"]).to eq("DomainDnsTestingWorker")
      end

      it 'queues domain even if it was recently tested' do
        # Domain already has DNS result
        domain.update!(dns: true)

        expect {
          post queue_single_dns_domain_path(domain)
        }.to change { DomainDnsTestingWorker.jobs.size }.by(1)

        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end

      it 'returns 404 for non-existent domain' do
        post queue_single_dns_domain_path(id: 99999)

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("Domain not found")
      end
    end

    context 'when service is inactive' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_testing").and_return(false)
      end

      it 'returns error when service is disabled' do
        expect {
          post queue_single_dns_domain_path(domain)
        }.not_to change { DomainDnsTestingWorker.jobs.size }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("DNS testing service is disabled")
      end
    end

    context 'when user is not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        post queue_single_dns_domain_path(domain)
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe 'POST /domains/:id/queue_single_mx' do
    context 'when service is active' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_mx_testing").and_return(true)
      end

      it 'queues the specific domain for MX testing' do
        expect {
          post queue_single_mx_domain_path(domain)
        }.to change { DomainMxTestingWorker.jobs.size }.by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["message"]).to eq("Domain queued for MX testing")
        expect(json["domain_id"]).to eq(domain.id)
        expect(json["service"]).to eq("mx")
      end

      it 'includes job information in response' do
        post queue_single_mx_domain_path(domain)

        json = JSON.parse(response.body)
        expect(json).to have_key("job_id")
        expect(json["worker"]).to eq("DomainMxTestingWorker")
      end

      it 'queues domain regardless of prerequisites' do
        # Even if DNS is not tested, still allow MX queueing
        domain.update!(dns: nil)

        expect {
          post queue_single_mx_domain_path(domain)
        }.to change { DomainMxTestingWorker.jobs.size }.by(1)

        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end

      it 'returns 404 for non-existent domain' do
        post queue_single_mx_domain_path(id: 99999)

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("Domain not found")
      end
    end

    context 'when service is inactive' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_mx_testing").and_return(false)
      end

      it 'returns error when service is disabled' do
        expect {
          post queue_single_mx_domain_path(domain)
        }.not_to change { DomainMxTestingWorker.jobs.size }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("MX testing service is disabled")
      end
    end
  end

  describe 'POST /domains/:id/queue_single_www' do
    context 'when service is active' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_a_record_testing").and_return(true)
      end

      it 'queues the specific domain for WWW testing' do
        expect {
          post queue_single_www_domain_path(domain)
        }.to change { DomainARecordTestingWorker.jobs.size }.by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["message"]).to eq("Domain queued for WWW testing")
        expect(json["domain_id"]).to eq(domain.id)
        expect(json["service"]).to eq("www")
      end

      it 'includes job information in response' do
        post queue_single_www_domain_path(domain)

        json = JSON.parse(response.body)
        expect(json).to have_key("job_id")
        expect(json["worker"]).to eq("DomainARecordTestingWorker")
      end

      it 'queues domain regardless of DNS status' do
        # Even if DNS is false, still allow WWW queueing for testing
        domain.update!(dns: false)

        expect {
          post queue_single_www_domain_path(domain)
        }.to change { DomainARecordTestingWorker.jobs.size }.by(1)

        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end

      it 'returns 404 for non-existent domain' do
        post queue_single_www_domain_path(id: 99999)

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("Domain not found")
      end
    end

    context 'when service is inactive' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_a_record_testing").and_return(false)
      end

      it 'returns error when service is disabled' do
        expect {
          post queue_single_www_domain_path(domain)
        }.not_to change { DomainARecordTestingWorker.jobs.size }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("WWW testing service is disabled")
      end
    end
  end

  describe 'Service Audit Integration' do
    before do
      allow(ServiceConfiguration).to receive(:active?).and_return(true)
    end

    it 'creates service audit log entry when queueing DNS test' do
      expect {
        post queue_single_dns_domain_path(domain)
      }.to change { ServiceAuditLog.count }.by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.auditable).to eq(domain)
      expect(audit_log.service_name).to eq("domain_testing")
      expect(audit_log.operation_type).to eq("queue_individual")
      expect(audit_log.status).to eq("pending")
    end

    it 'creates service audit log entry when queueing MX test' do
      expect {
        post queue_single_mx_domain_path(domain)
      }.to change { ServiceAuditLog.count }.by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.auditable).to eq(domain)
      expect(audit_log.service_name).to eq("domain_mx_testing")
      expect(audit_log.operation_type).to eq("queue_individual")
    end

    it 'creates service audit log entry when queueing WWW test' do
      expect {
        post queue_single_www_domain_path(domain)
      }.to change { ServiceAuditLog.count }.by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.auditable).to eq(domain)
      expect(audit_log.service_name).to eq("domain_a_record_testing")
      expect(audit_log.operation_type).to eq("queue_individual")
    end
  end

  describe 'Rate Limiting' do
    before do
      allow(ServiceConfiguration).to receive(:active?).and_return(true)
    end

    it 'allows multiple tests for same domain' do
      # First request
      post queue_single_dns_domain_path(domain)
      expect(response).to have_http_status(:ok)

      # Second request should also succeed
      post queue_single_dns_domain_path(domain)
      expect(response).to have_http_status(:ok)

      expect(DomainDnsTestingWorker.jobs.size).to eq(2)
    end
  end

  describe 'Response Format' do
    before do
      allow(ServiceConfiguration).to receive(:active?).and_return(true)
    end

    it 'returns consistent JSON format for successful DNS queue' do
      post queue_single_dns_domain_path(domain)

      json = JSON.parse(response.body)
      expect(json).to include(
        "success" => true,
        "message" => "Domain queued for DNS testing",
        "domain_id" => domain.id,
        "service" => "dns",
        "job_id" => be_a(String),
        "worker" => "DomainDnsTestingWorker"
      )
    end

    it 'returns consistent JSON format for successful MX queue' do
      post queue_single_mx_domain_path(domain)

      json = JSON.parse(response.body)
      expect(json).to include(
        "success" => true,
        "message" => "Domain queued for MX testing",
        "domain_id" => domain.id,
        "service" => "mx",
        "job_id" => be_a(String),
        "worker" => "DomainMxTestingWorker"
      )
    end

    it 'returns consistent JSON format for successful WWW queue' do
      post queue_single_www_domain_path(domain)

      json = JSON.parse(response.body)
      expect(json).to include(
        "success" => true,
        "message" => "Domain queued for WWW testing",
        "domain_id" => domain.id,
        "service" => "www",
        "job_id" => be_a(String),
        "worker" => "DomainARecordTestingWorker"
      )
    end
  end
end
