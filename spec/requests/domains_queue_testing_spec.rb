# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Domain Queue Testing', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    # Clear Sidekiq jobs before each test
    Sidekiq::Worker.clear_all
  end

  describe 'POST /domains/queue_dns_testing' do
    context 'when service is active' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_testing").and_return(true)
      end

      it 'queues domains needing DNS testing' do
        domains = create_list(:domain, 3, dns: nil)
        
        expect {
          post queue_dns_testing_domains_path, params: { count: 10 }
        }.to change { DomainDnsTestingWorker.jobs.size }.by(3)
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["queued_count"]).to eq(3)
        expect(json["message"]).to eq("Queued 3 domains for DNS testing")
      end
      
      it 'respects count parameter' do
        create_list(:domain, 5, dns: nil)
        
        expect {
          post queue_dns_testing_domains_path, params: { count: 2 }
        }.to change { DomainDnsTestingWorker.jobs.size }.by(2)
        
        json = JSON.parse(response.body)
        expect(json["queued_count"]).to eq(2)
      end
      
      it 'uses default count of 100 when not specified' do
        create_list(:domain, 150, dns: nil)
        
        expect {
          post queue_dns_testing_domains_path
        }.to change { DomainDnsTestingWorker.jobs.size }.by(100)
      end
      
      it 'returns queue stats in response' do
        post queue_dns_testing_domains_path, params: { count: 0 }
        
        json = JSON.parse(response.body)
        expect(json).to have_key("queue_stats")
      end
      
      it 'handles case when no domains need testing' do
        # All domains already tested
        create_list(:domain, 3, dns: true)
        
        post queue_dns_testing_domains_path, params: { count: 10 }
        
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["queued_count"]).to eq(0)
        expect(json["message"]).to eq("Queued 0 domains for DNS testing")
      end
    end
    
    context 'when service is inactive' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_testing").and_return(false)
      end
      
      it 'returns error when service is disabled' do
        create_list(:domain, 3, dns: nil)
        
        expect {
          post queue_dns_testing_domains_path
        }.not_to change { DomainDnsTestingWorker.jobs.size }
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("DNS testing service is disabled")
      end
    end
  end

  describe 'POST /domains/queue_mx_testing' do
    context 'when service is active' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_mx_testing").and_return(true)
      end

      it 'queues domains needing MX testing' do
        # Create domains that need MX testing (based on DomainMxTestingService logic)
        domains = create_list(:domain, 3, mx: nil)
        
        expect {
          post queue_mx_testing_domains_path, params: { count: 10 }
        }.to change { DomainMxTestingWorker.jobs.size }.by(3)
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["queued_count"]).to eq(3)
        expect(json["message"]).to eq("Queued 3 domains for MX testing")
      end
      
      it 'respects count parameter' do
        create_list(:domain, 5, mx: nil)
        
        expect {
          post queue_mx_testing_domains_path, params: { count: 2 }
        }.to change { DomainMxTestingWorker.jobs.size }.by(2)
        
        json = JSON.parse(response.body)
        expect(json["queued_count"]).to eq(2)
      end
      
      it 'uses default count of 100 when not specified' do
        create_list(:domain, 150, mx: nil)
        
        expect {
          post queue_mx_testing_domains_path
        }.to change { DomainMxTestingWorker.jobs.size }.by(100)
      end
    end
    
    context 'when service is inactive' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_mx_testing").and_return(false)
      end
      
      it 'returns error when service is disabled' do
        create_list(:domain, 3, mx: nil)
        
        expect {
          post queue_mx_testing_domains_path
        }.not_to change { DomainMxTestingWorker.jobs.size }
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("MX testing service is disabled")
      end
    end
  end

  describe 'POST /domains/queue_a_record_testing' do
    context 'when service is active' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_a_record_testing").and_return(true)
      end

      it 'queues domains needing A record testing' do
        # Create domains that need A record testing (DNS active but www is nil)
        domains = create_list(:domain, 3, dns: true, www: nil)
        
        expect {
          post queue_a_record_testing_domains_path, params: { count: 10 }
        }.to change { DomainARecordTestingWorker.jobs.size }.by(3)
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["queued_count"]).to eq(3)
        expect(json["message"]).to eq("Queued 3 domains for A Record testing")
      end
      
      it 'only queues domains with dns=true and www=nil' do
        # These should be queued
        create_list(:domain, 2, dns: true, www: nil)
        # These should NOT be queued
        create_list(:domain, 2, dns: false, www: nil)
        create_list(:domain, 2, dns: true, www: true)
        
        expect {
          post queue_a_record_testing_domains_path, params: { count: 10 }
        }.to change { DomainARecordTestingWorker.jobs.size }.by(2)
        
        json = JSON.parse(response.body)
        expect(json["queued_count"]).to eq(2)
      end
      
      it 'respects count parameter' do
        create_list(:domain, 5, dns: true, www: nil)
        
        expect {
          post queue_a_record_testing_domains_path, params: { count: 2 }
        }.to change { DomainARecordTestingWorker.jobs.size }.by(2)
        
        json = JSON.parse(response.body)
        expect(json["queued_count"]).to eq(2)
      end
    end
    
    context 'when service is inactive' do
      before do
        allow(ServiceConfiguration).to receive(:active?).with("domain_a_record_testing").and_return(false)
      end
      
      it 'returns error when service is disabled' do
        create_list(:domain, 3, dns: true, www: nil)
        
        expect {
          post queue_a_record_testing_domains_path
        }.not_to change { DomainARecordTestingWorker.jobs.size }
        
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to eq("A Record testing service is disabled")
      end
    end
  end
end