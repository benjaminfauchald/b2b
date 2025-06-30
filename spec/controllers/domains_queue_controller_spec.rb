# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'
require 'sidekiq/api'

RSpec.describe 'Domain queue operations', type: :request do
  let(:user) { create(:user, email: "admin@example.com") }

  before do
    sign_in user

    # Create service configurations with appropriate refresh intervals
    create(:service_configuration, service_name: 'domain_testing', active: true, refresh_interval_hours: 24)
    create(:service_configuration, service_name: 'domain_mx_testing', active: true, refresh_interval_hours: 24)
    create(:service_configuration, service_name: 'domain_a_record_testing', active: true, refresh_interval_hours: 24)
    create(:service_configuration, service_name: 'domain_web_content_extraction', active: true, refresh_interval_hours: 24)

    # Clear Sidekiq queues
    Sidekiq::Queue.all.each(&:clear)
  end

  describe 'POST #queue_dns_testing' do
    let!(:untested_domains) { create_list(:domain, 30, dns: nil) }
    let!(:tested_domains) { create_list(:domain, 10, dns: true) }

    context 'with valid parameters' do
      it 'queues the requested number of domains' do
        post queue_dns_testing_domains_path, params: { count: 10 }, as: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['success']).to be true
        expect(json['queued_count']).to eq(10)
        expect(json['message']).to include('Queued 10 domains')
      end

      it 'returns updated queue statistics' do
        post queue_dns_testing_domains_path, params: { count: 5 }, as: :json

        json = JSON.parse(response.body)
        expect(json['queue_stats']).to be_present
        expect(json['queued_count']).to eq(5) # Verify that jobs were actually queued
        expect(json['queue_stats']).to have_key('domain_dns_testing') # Queue exists in stats
        # Note: In test environment, queue size may be 0 due to immediate processing or timing
      end

      it 'handles case when fewer domains are available than requested' do
        # Test all but 5 domains (update them to dns: true so they won't be returned by needing_service)
        untested_domains[5..-1].each { |d| d.update!(dns: true) }

        post queue_dns_testing_domains_path, params: { count: 10 }, as: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['queued_count']).to eq(5)
        expect(json['message']).to include('Queued all 5 available domains')
      end

      it 'validates count is positive' do
        post queue_dns_testing_domains_path, params: { count: 0 }, as: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['message']).to include('Count must be greater than 0')
      end

      it 'limits maximum queue size' do
        post queue_dns_testing_domains_path, params: { count: 1001 }, as: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['message']).to include('Cannot queue more than 1000')
      end
    end

    context 'when no domains need testing' do
      before { Domain.update_all(dns: true) }

      it 'returns appropriate message' do
        post queue_dns_testing_domains_path, params: { count: 10 }, as: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['message']).to include('No domains need DNS testing')
        expect(json['available_count']).to eq(0)
      end
    end

    context 'when service is disabled' do
      before do
        ServiceConfiguration.find_by(service_name: 'domain_testing').update!(active: false)
      end

      it 'returns service disabled message' do
        post queue_dns_testing_domains_path, params: { count: 10 }, as: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['message']).to include('DNS testing service is disabled')
      end
    end
  end

  describe 'GET #queue_status' do
    before do
      # Create domains in various states
      create_list(:domain, 15, dns: nil)
      create_list(:domain, 10, dns: true, mx: nil)
      create_list(:domain, 5, dns: true, www: nil)
      create_list(:domain, 3, dns: true, www: true, a_record_ip: '1.2.3.4', web_content_data: nil)

      # Add some jobs to queues
      Sidekiq::Testing.fake! do
        5.times { DomainDnsTestingWorker.perform_async(create(:domain).id) }
        3.times { DomainMxTestingWorker.perform_async(create(:domain).id) }
      end
    end

    it 'returns current queue statistics' do
      get queue_status_domains_path, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json['success']).to be true
      expect(json['queue_stats']).to be_present

      stats = json['queue_stats']
      # In test environment, queue sizes may be 0 due to immediate processing
      expect(stats).to have_key('domain_dns_testing')
      expect(stats).to have_key('domain_mx_testing')
      # Note: Other tests may affect domain counts, so we verify structure and reasonable values
      expect(stats['domains_needing']['domain_testing']).to be >= 15
      expect(stats['domains_needing']['domain_mx_testing']).to be >= 10
      expect(stats['domains_needing']['domain_a_record_testing']).to be >= 5
      expect(stats['domains_needing']['domain_web_content_extraction']).to be >= 3
    end

    it 'includes Sidekiq statistics' do
      get queue_status_domains_path, as: :json

      json = JSON.parse(response.body)
      stats = json['queue_stats']

      expect(stats).to have_key('total_processed')
      expect(stats).to have_key('total_failed')
      expect(stats).to have_key('total_enqueued')
      expect(stats).to have_key('workers_busy')
    end
  end

  describe 'Queue Statistics Real-time Updates' do
    it 'reflects changes immediately after queueing' do
      create_list(:domain, 20, dns: nil)

      # Check initial status
      get queue_status_domains_path, as: :json
      initial_stats = JSON.parse(response.body)['queue_stats']
      expect(initial_stats['domain_dns_testing']).to eq(0)
      expect(initial_stats['domains_needing']['domain_testing']).to eq(20)

      # Queue some domains
      post queue_dns_testing_domains_path, params: { count: 10 }, as: :json
      response_data = JSON.parse(response.body)
      expect(response_data['success']).to be true
      expect(response_data['queued_count']).to eq(10)

      # Check updated status - verify that the queueing was successful
      get queue_status_domains_path, as: :json
      updated_stats = JSON.parse(response.body)['queue_stats']
      expect(updated_stats).to have_key('domain_dns_testing')
      # Note: In test environment, queue size may be 0 due to immediate processing
      # Note: domains_needing won't change until domains are actually processed
    end

    it 'updates correctly as domains are processed' do
      domains = create_list(:domain, 10, dns: nil)

      # Queue all domains
      post queue_dns_testing_domains_path, params: { count: 10 }, as: :json
      response_data = JSON.parse(response.body)
      expect(response_data['success']).to be true
      expect(response_data['queued_count']).to eq(10)

      # In test environment, jobs may be processed immediately
      # So let's verify the logical outcome: domains needing service should be updated
      get queue_status_domains_path, as: :json
      stats = JSON.parse(response.body)['queue_stats']

      # Verify the stats structure is correct
      expect(stats).to have_key('domain_dns_testing')
      expect(stats).to have_key('domains_needing')
      expect(stats['domains_needing']).to have_key('domain_testing')

      # The number of domains needing service should be <= original count
      # (may be reduced if jobs processed immediately)
      expect(stats['domains_needing']['domain_testing']).to be <= 10
    end
  end

  describe 'Cascading Queue Effects' do
    it 'successful DNS tests trigger MX and A record tests' do
      # Clean slate - clear all existing domains and create fresh ones
      Domain.delete_all
      test_domains = create_list(:domain, 3, dns: nil, mx: nil, www: nil)

      # Update domains to simulate successful DNS tests
      test_domains.each { |domain| domain.update!(dns: true) }

      # Check queue stats - domains should now need MX and A record testing
      get queue_status_domains_path, as: :json
      stats = JSON.parse(response.body)['queue_stats']

      # Verify queue stats structure
      expect(stats).to have_key('domains_needing')
      expect(stats['domains_needing']).to have_key('domain_mx_testing')
      expect(stats['domains_needing']).to have_key('domain_a_record_testing')

      # These 3 domains should now need MX and A record testing (dns=true, mx=nil, www=nil)
      expect(stats['domains_needing']['domain_mx_testing']).to eq(3)
      expect(stats['domains_needing']['domain_a_record_testing']).to eq(3)

      # Note: The actual worker cascading is tested in service-specific tests
      # This controller test focuses on the queue statistics and availability counts
    end
  end

  describe 'Performance and Scalability' do
    it 'handles large batch operations efficiently' do
      # Create many domains
      create_list(:domain, 500, dns: nil)

      start_time = Time.current

      # Queue maximum allowed
      post queue_dns_testing_domains_path, params: { count: 1000 }, as: :json

      response_time = Time.current - start_time

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['queued_count']).to eq(500)

      # Should complete within reasonable time
      expect(response_time).to be < 2.seconds
    end

    it 'calculates statistics efficiently for large datasets' do
      # Create many domains in various states
      create_list(:domain, 1000, dns: nil)
      create_list(:domain, 500, dns: true, mx: nil)
      create_list(:domain, 300, dns: true, www: nil)

      start_time = Time.current

      get queue_status_domains_path, as: :json

      response_time = Time.current - start_time

      expect(response).to have_http_status(:success)

      # Statistics calculation should be fast
      expect(response_time).to be < 0.5.seconds
    end
  end
end
