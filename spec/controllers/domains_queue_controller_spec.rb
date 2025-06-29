# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'
require 'sidekiq/api'

RSpec.describe DomainsController, type: :controller do
  let(:user) { create(:user, admin: true) }

  before do
    sign_in user

    # Create service configurations
    create(:service_configuration, service_name: 'domain_testing', active: true)
    create(:service_configuration, service_name: 'domain_mx_testing', active: true)
    create(:service_configuration, service_name: 'domain_a_record_testing', active: true)
    create(:service_configuration, service_name: 'domain_web_content_extraction', active: true)

    # Clear Sidekiq queues
    Sidekiq::Queue.all.each(&:clear)
  end

  describe 'POST #queue_dns_testing' do
    let!(:untested_domains) { create_list(:domain, 30, dns: nil) }
    let!(:tested_domains) { create_list(:domain, 10, dns: true) }

    context 'with valid parameters' do
      it 'queues the requested number of domains' do
        post :queue_dns_testing, params: { count: 10 }, format: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['success']).to be true
        expect(json['queued_count']).to eq(10)
        expect(json['message']).to include('Queued 10 domains')
      end

      it 'returns updated queue statistics' do
        post :queue_dns_testing, params: { count: 5 }, format: :json

        json = JSON.parse(response.body)
        expect(json['queue_stats']).to be_present
        expect(json['queue_stats']['domain_dns_testing']).to eq(5)
      end

      it 'handles case when fewer domains are available than requested' do
        # Test all but 5 domains
        untested_domains[5..-1].each { |d| d.update!(dns: true) }

        post :queue_dns_testing, params: { count: 10 }, format: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['queued_count']).to eq(5)
        expect(json['message']).to include('Queued all 5 available domains')
      end

      it 'validates count is positive' do
        post :queue_dns_testing, params: { count: 0 }, format: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['message']).to include('Count must be greater than 0')
      end

      it 'limits maximum queue size' do
        post :queue_dns_testing, params: { count: 1001 }, format: :json

        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['message']).to include('Cannot queue more than 1000')
      end
    end

    context 'when no domains need testing' do
      before { Domain.update_all(dns: true) }

      it 'returns appropriate message' do
        post :queue_dns_testing, params: { count: 10 }, format: :json

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
        post :queue_dns_testing, params: { count: 10 }, format: :json

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
      get :queue_status, format: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json['success']).to be true
      expect(json['queue_stats']).to be_present

      stats = json['queue_stats']
      expect(stats['domain_dns_testing']).to eq(5)
      expect(stats['domain_mx_testing']).to eq(3)
      expect(stats['domains_needing']['domain_testing']).to eq(15)
      expect(stats['domains_needing']['domain_mx_testing']).to eq(10)
      expect(stats['domains_needing']['domain_a_record_testing']).to eq(5)
      expect(stats['domains_needing']['domain_web_content_extraction']).to eq(3)
    end

    it 'includes Sidekiq statistics' do
      get :queue_status, format: :json

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
      get :queue_status, format: :json
      initial_stats = JSON.parse(response.body)['queue_stats']
      expect(initial_stats['domain_dns_testing']).to eq(0)
      expect(initial_stats['domains_needing']['domain_testing']).to eq(20)

      # Queue some domains
      post :queue_dns_testing, params: { count: 10 }, format: :json

      # Check updated status
      get :queue_status, format: :json
      updated_stats = JSON.parse(response.body)['queue_stats']
      expect(updated_stats['domain_dns_testing']).to eq(10)
      # Note: domains_needing won't change until domains are actually processed
    end

    it 'updates correctly as domains are processed' do
      domains = create_list(:domain, 10, dns: nil)

      # Queue all domains
      post :queue_dns_testing, params: { count: 10 }, format: :json

      # Process half the domains
      Sidekiq::Testing.inline! do
        5.times do
          job = Sidekiq::Queue.new('domain_dns_testing').first
          break unless job
          DomainDnsTestingWorker.new.perform(job.args.first)
          job.delete
        end
      end

      # Check status
      get :queue_status, format: :json
      stats = JSON.parse(response.body)['queue_stats']

      # Queue should have 5 remaining
      expect(stats['domain_dns_testing']).to eq(5)

      # Domains needing should have decreased by processed amount
      processed_count = Domain.where.not(dns: nil).count
      remaining_need = Domain.where(dns: nil).count
      expect(stats['domains_needing']['domain_testing']).to eq(remaining_need)
    end
  end

  describe 'Cascading Queue Effects' do
    let!(:domains) { create_list(:domain, 5, dns: nil) }

    before do
      # Mock successful DNS tests
      allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([ 'fake_record' ])
    end

    it 'successful DNS tests trigger MX and A record tests' do
      # Spy on worker calls
      allow(DomainMxTestingWorker).to receive(:perform_async).and_call_original
      allow(DomainARecordTestingWorker).to receive(:perform_async).and_call_original

      # Process DNS tests
      Sidekiq::Testing.inline! do
        domains.each do |domain|
          DomainDnsTestingWorker.perform_async(domain.id)
        end
      end

      # Should have queued follow-up tests
      expect(DomainMxTestingWorker).to have_received(:perform_async).exactly(5).times
      expect(DomainARecordTestingWorker).to have_received(:perform_async).exactly(5).times

      # Check queue stats
      get :queue_status, format: :json
      stats = JSON.parse(response.body)['queue_stats']

      # DNS queue should be empty
      expect(stats['domain_dns_testing']).to eq(0)
      # Domains should now need MX and A record testing
      expect(stats['domains_needing']['domain_mx_testing']).to eq(5)
      expect(stats['domains_needing']['domain_a_record_testing']).to eq(5)
    end
  end

  describe 'Performance and Scalability' do
    it 'handles large batch operations efficiently' do
      # Create many domains
      create_list(:domain, 500, dns: nil)

      start_time = Time.current

      # Queue maximum allowed
      post :queue_dns_testing, params: { count: 1000 }, format: :json

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

      get :queue_status, format: :json

      response_time = Time.current - start_time

      expect(response).to have_http_status(:success)

      # Statistics calculation should be fast
      expect(response_time).to be < 0.5.seconds
    end
  end
end
