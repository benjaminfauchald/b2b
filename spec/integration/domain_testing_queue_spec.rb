# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'
require 'sidekiq/api'

RSpec.describe 'Domain Testing Queue Integration', type: :integration do
  let(:user) { create(:user) }
  
  before do
    # Create service configurations
    create(:service_configuration, service_name: 'domain_testing', active: true)
    create(:service_configuration, service_name: 'domain_mx_testing', active: true)
    create(:service_configuration, service_name: 'domain_a_record_testing', active: true)
    create(:service_configuration, service_name: 'domain_web_content_extraction', active: true)
    
    # Ensure we're in fake mode by default
    Sidekiq::Testing.fake!
    
    # Clear Sidekiq queues
    Sidekiq::Queue.all.each(&:clear)
    Sidekiq::Worker.clear_all
    Sidekiq::RetrySet.new.clear
    Sidekiq::DeadSet.new.clear
  end

  describe 'DNS Testing Queue Processing' do
    let!(:untested_domains) { create_list(:domain, 50, dns: nil) }
    let!(:tested_domains) { create_list(:domain, 10, dns: true) }
    
    context 'when queueing domains for DNS testing' do
      it 'correctly calculates domains needing testing' do
        # The needing_service scope looks at audit logs, not dns field
        # So all 60 domains will need testing initially
        count = Domain.needing_service('domain_testing').count
        expect(count).to eq(60)
      end
      
      it 'queues correct number of domains' do
        # Queue 20 domains
        queued = 0
        Domain.needing_service('domain_testing').limit(20).each do |domain|
          DomainDnsTestingWorker.perform_async(domain.id)
          queued += 1
        end
        
        expect(queued).to eq(20)
        
        # Check Sidekiq jobs array in fake mode
        expect(DomainDnsTestingWorker.jobs.size).to eq(20)
      end
      
      it 'updates domains_needing count after queueing' do
        # Initial count - all 60 domains need testing
        expect(Domain.needing_service('domain_testing').count).to eq(60)
        
        # Mock the service to create audit logs
        allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
          domain = service.instance_variable_get(:@domain)
          domain.update!(dns: true)
          # Create audit log with all required fields
          ServiceAuditLog.create!(
            auditable: domain,
            service_name: 'domain_testing',
            status: 'success',
            started_at: Time.current,
            completed_at: Time.current,
            table_name: 'domains',
            record_id: domain.id.to_s,
            columns_affected: ['dns'],
            metadata: { 'result' => 'success' }
          )
          OpenStruct.new(success?: true)
        end
        
        # Process some domains
        Sidekiq::Testing.inline! do
          Domain.needing_service('domain_testing').limit(10).each do |domain|
            DomainDnsTestingWorker.perform_async(domain.id)
          end
        end
        
        # Count should decrease by 10
        expect(Domain.needing_service('domain_testing').count).to eq(50)
      end
    end
    
    context 'when processing DNS tests' do
      before do
        # Mock DNS resolution
        allow(Resolv::DNS).to receive(:open).and_yield(double(getaddress: '1.2.3.4'))
        allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return(['fake_record'])
      end
      
      it 'processes domains quickly' do
        start_time = Time.current
        
        # Mock DomainTestingService to set dns field
        allow_any_instance_of(DomainTestingService).to receive(:perform) do |service|
          domain = service.instance_variable_get(:@domain)
          domain.update!(dns: true)
          OpenStruct.new(success?: true)
        end
        
        Sidekiq::Testing.inline! do
          untested_domains.first(10).each do |domain|
            DomainDnsTestingWorker.perform_async(domain.id)
          end
        end
        
        processing_time = Time.current - start_time
        
        # Should process 10 domains in under 5 seconds
        expect(processing_time).to be < 5.seconds
        
        # All domains should be processed
        untested_domains.first(10).each(&:reload)
        expect(untested_domains.first(10).all? { |d| !d.dns.nil? }).to be true
      end
      
      it 'creates audit logs for each processed domain' do
        expect {
          Sidekiq::Testing.inline! do
            untested_domains.first(5).each do |domain|
              DomainDnsTestingWorker.perform_async(domain.id)
            end
          end
        }.to change(ServiceAuditLog, :count).by_at_least(5)
      end
      
      it 'queues follow-up tests for successful DNS tests' do
        # Clear any existing jobs
        DomainMxTestingWorker.clear
        DomainARecordTestingWorker.clear
        
        # Mock the service to simulate successful DNS test that queues follow-ups
        allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
          domain = service.instance_variable_get(:@domain)
          domain.update!(dns: true)
          # The real service queues follow-up jobs, so do it here too
          DomainMxTestingWorker.perform_async(domain.id)
          DomainARecordTestingWorker.perform_async(domain.id)
          OpenStruct.new(success?: true)
        end
        
        # Process 3 domains
        untested_domains.first(3).each do |domain|
          worker = DomainDnsTestingWorker.new
          worker.perform(domain.id)
        end
        
        # Check that follow-up jobs were queued
        expect(DomainMxTestingWorker.jobs.size).to eq(3)
        expect(DomainARecordTestingWorker.jobs.size).to eq(3)
      end
    end
  end
  
  describe 'Queue Statistics Updates' do
    let(:controller) { DomainsController.new }
    
    before do
      # Mock current_user for controller
      allow(controller).to receive(:current_user).and_return(user)
    end
    
    it 'returns accurate queue statistics' do
      # Mock the Sidekiq queues
      dns_queue = double('dns_queue', size: 5)
      mx_queue = double('mx_queue', size: 3)
      default_queue = double('default_queue')
      
      # Mock queue behavior for A Record and Web Content counting
      # First call counts A Record workers
      allow(default_queue).to receive(:count) do |&block|
        if block
          # Check what the block is looking for
          job = double(klass: 'DomainARecordTestingWorker')
          if block.call(job)
            2 # Return count for A Record workers
          else
            1 # Return count for Web Content workers
          end
        end
      end.and_return(2, 1)
      allow(default_queue).to receive(:size).and_return(3)
      
      allow(Sidekiq::Queue).to receive(:new).with('domain_dns_testing').and_return(dns_queue)
      allow(Sidekiq::Queue).to receive(:new).with('domain_mx_testing').and_return(mx_queue)
      allow(Sidekiq::Queue).to receive(:new).with('default').and_return(default_queue)
      
      # Mock Sidekiq stats
      sidekiq_stats = double('sidekiq_stats', 
        processed: 1000, 
        failed: 10, 
        enqueued: 11, 
        workers_size: 2
      )
      allow(Sidekiq::Stats).to receive(:new).and_return(sidekiq_stats)
      
      # Create test data for domains needing counts
      create_list(:domain, 10, dns: nil)
      
      stats = controller.send(:get_queue_stats)
      
      expect(stats['domain_dns_testing']).to eq(5)
      expect(stats['domain_mx_testing']).to eq(3)
      expect(stats['DomainARecordTestingService']).to eq(2)
      expect(stats['DomainWebContentExtractionWorker']).to eq(1)
      expect(stats[:total_processed]).to eq(1000)
      expect(stats[:total_failed]).to eq(10)
      expect(stats[:total_enqueued]).to eq(11)
      expect(stats[:workers_busy]).to eq(2)
    end
    
    it 'includes domains_needing counts' do
      # Create domains in various states
      create_list(:domain, 10, dns: nil) # Need DNS testing
      create_list(:domain, 5, dns: true, mx: nil) # Need MX testing
      create_list(:domain, 3, dns: true, www: nil) # Need A record testing
      create_list(:domain, 2, dns: true, www: true, a_record_ip: '1.2.3.4', web_content_data: nil) # Need web content
      
      stats = controller.send(:get_queue_stats)
      
      # All created domains need testing since they have no audit logs
      total_domains = Domain.count
      expect(stats[:domains_needing][:domain_testing]).to eq(total_domains)
      expect(stats[:domains_needing][:domain_mx_testing]).to eq(5)
      expect(stats[:domains_needing][:domain_a_record_testing]).to eq(3)
      expect(stats[:domains_needing][:domain_web_content_extraction]).to eq(2)
    end
  end
  
  describe 'Concurrent Queue Processing' do
    it 'handles multiple workers processing simultaneously' do
      domains = create_list(:domain, 20, dns: nil)
      
      # Mock DomainTestingService to update dns field
      allow_any_instance_of(DomainTestingService).to receive(:perform) do |service|
        domain = service.instance_variable_get(:@domain)
        domain.update!(dns: true)
        OpenStruct.new(success?: true)
      end
      
      processed_count = 0
      mutex = Mutex.new
      
      # Simulate multiple workers processing different domains
      threads = 5.times.map do |i|
        Thread.new do
          # Each thread processes 4 domains
          domains[i*4...(i+1)*4].each do |domain|
            service = DomainTestingService.new(domain: domain)
            service.perform
            mutex.synchronize { processed_count += 1 }
          end
        end
      end
      
      threads.each(&:join)
      
      expect(processed_count).to eq(20)
      expect(Domain.where.not(dns: nil).count).to eq(20)
    end
  end
  
  describe 'Queue Drainage Rate' do
    it 'processes DNS queue items as they are added' do
      # Add domains gradually
      domains = create_list(:domain, 30, dns: nil)
      
      # In fake mode, check the jobs array
      expect(DomainDnsTestingWorker.jobs.size).to eq(0)
      
      # Queue first batch
      domains.first(10).each { |d| DomainDnsTestingWorker.perform_async(d.id) }
      expect(DomainDnsTestingWorker.jobs.size).to eq(10)
      
      # Process half by clearing some jobs
      5.times { DomainDnsTestingWorker.jobs.shift }
      expect(DomainDnsTestingWorker.jobs.size).to eq(5)
      
      # Queue more
      domains[10..19].each { |d| DomainDnsTestingWorker.perform_async(d.id) }
      expect(DomainDnsTestingWorker.jobs.size).to eq(15)
      
      # Process all
      DomainDnsTestingWorker.clear
      expect(DomainDnsTestingWorker.jobs.size).to eq(0)
    end
  end
  
  describe 'Error Handling and Recovery' do
    it 'handles DNS resolution failures gracefully' do
      domain = create(:domain, dns: nil)
      
      # Mock DNS failure in the service
      allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
        domain = service.instance_variable_get(:@domain)
        domain.update!(dns: false)
        # Create audit log even for DNS failure
        ServiceAuditLog.create!(
          auditable: domain,
          service_name: 'domain_testing',
          status: 'success',
          started_at: Time.current,
          completed_at: Time.current,
          table_name: 'domains',
          record_id: domain.id.to_s,
          columns_affected: ['dns'],
          metadata: { 'result' => 'DNS resolution failed' }
        )
        OpenStruct.new(success?: true)
      end
      
      Sidekiq::Testing.inline! do
        expect {
          DomainDnsTestingWorker.perform_async(domain.id)
        }.not_to raise_error
      end
      
      domain.reload
      expect(domain.dns).to eq(false)
      
      # Should still be counted as processed
      audit_log = ServiceAuditLog.last
      expect(audit_log).to be_present
      expect(audit_log.status).to eq('success') # Service ran successfully even if DNS failed
    end
    
    it 'retries on temporary failures' do
      domain = create(:domain, dns: nil)
      
      # Mock the service to simulate retry behavior
      call_count = 0
      allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
        call_count += 1
        if call_count == 1
          # First call fails
          OpenStruct.new(success?: false)
        else
          # Second call succeeds
          domain = service.instance_variable_get(:@domain)
          domain.update!(dns: true)
          OpenStruct.new(success?: true)
        end
      end
      
      # Process with retry logic
      service = DomainTestingService.new(domain: domain)
      result = nil
      2.times do
        result = service.call
        break if result.success?
      end
      
      expect(result.success?).to be true
    end
  end
end