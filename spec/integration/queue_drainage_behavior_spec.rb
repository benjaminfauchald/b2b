# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'
require 'sidekiq/api'
require 'ostruct'

RSpec.describe 'Queue Drainage Behavior', type: :integration do
  before do
    # Create service configurations
    create(:service_configuration, service_name: 'domain_testing', active: true)
    create(:service_configuration, service_name: 'domain_mx_testing', active: true)
    create(:service_configuration, service_name: 'domain_a_record_testing', active: true)
    
    # Clear all queues
    Sidekiq::Queue.all.each(&:clear)
    
    # Mock DNS resolution
    allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return(['fake_record'])
    
    # Setup basic queue mocks
    setup_queue_mocks
  end
  
  def setup_queue_mocks
    # Mock Sidekiq stats
    allow(Sidekiq::Stats).to receive(:new).and_return(
      double(processed: 1000, failed: 10, enqueued: 0, workers_size: 2)
    )
  end
  
  def mock_all_queues(queue_sizes, default_a_record_count: 0)
    queue_sizes.each do |queue_name, size|
      if queue_name == 'default' && default_a_record_count > 0
        # Special handling for default queue with A record workers
        queue_double = double(size: size)
        allow(queue_double).to receive(:count) do |&block|
          if block
            job = double(klass: 'DomainARecordTestingWorker')
            block.call(job) ? default_a_record_count : 0
          else
            size
          end
        end
        allow(Sidekiq::Queue).to receive(:new).with(queue_name).and_return(queue_double)
      else
        queue_double = double(size: size)
        # Always mock count method for default queue
        if queue_name == 'default'
          allow(queue_double).to receive(:count) do |&block|
            if block
              job = double(klass: 'DomainWebContentExtractionWorker')
              block.call(job) ? 0 : 0
            else
              0
            end
          end
        end
        allow(Sidekiq::Queue).to receive(:new).with(queue_name).and_return(queue_double)
      end
    end
  end
  
  describe 'DNS Queue Drainage vs Stats Updates' do
    let(:controller) { DomainsController.new }
    let(:user) { create(:user) }
    
    before do
      allow(controller).to receive(:current_user).and_return(user)
    end
    
    it 'shows correct queue counts as domains are processed' do
      # Create 50 untested domains
      domains = create_list(:domain, 50, dns: nil)
      
      # Initial state - no domains in queue
      stats = controller.send(:get_queue_stats)
      expect(stats['domain_dns_testing']).to eq(0)
      expect(stats[:domains_needing][:domain_testing]).to eq(50)
      
      # Queue 30 domains
      Sidekiq::Testing.fake!
      domains.first(30).each { |d| DomainDnsTestingWorker.perform_async(d.id) }
      
      # Mock all queues for get_queue_stats
      mock_all_queues({
        'domain_dns_testing' => DomainDnsTestingWorker.jobs.size,
        'domain_mx_testing' => 0,
        'domain_a_record_testing' => 0,
        'default' => 0
      })
      
      # Check queue stats - should show 30 in queue, still 50 needing
      stats = controller.send(:get_queue_stats)
      expect(stats['domain_dns_testing']).to eq(30)
      expect(stats[:domains_needing][:domain_testing]).to eq(50) # Not processed yet
      
      # Process 10 domains
      # Mock the service to set dns field
      allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
        domain = service.instance_variable_get(:@domain)
        domain.update!(dns: true)
        # Create audit log to mark as processed
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
      
      # Process first 10 jobs
      10.times do |i|
        DomainDnsTestingWorker.new.perform(domains[i].id)
      end
      
      # Clear those jobs from the fake queue
      10.times { DomainDnsTestingWorker.jobs.shift }
      
      # Update the mock to reflect new queue size
      mock_all_queues({
        'domain_dns_testing' => 20,
        'domain_mx_testing' => 0,
        'domain_a_record_testing' => 0,
        'default' => 0
      })
      
      # Check stats again
      stats = controller.send(:get_queue_stats)
      expect(stats['domain_dns_testing']).to eq(20) # 30 - 10 processed
      expect(stats[:domains_needing][:domain_testing]).to eq(40) # 50 - 10 processed
      
      # Process remaining 20 domains (30 total were queued, 10 already processed)
      DomainDnsTestingWorker.clear
      
      # Mark remaining 20 as processed with audit logs
      domains[10...30].each do |domain|
        domain.update!(dns: true)
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
      end
      
      # Mock empty queue
      mock_all_queues({
        'domain_dns_testing' => 0,
        'domain_mx_testing' => 0,
        'domain_a_record_testing' => 0,
        'default' => 0
      })
      
      # Final check
      stats = controller.send(:get_queue_stats)
      expect(stats['domain_dns_testing']).to eq(0)
      expect(stats[:domains_needing][:domain_testing]).to eq(20) # Only unqueued domains
    end
    
    it 'maintains consistency between queue size and domains needing service' do
      # Create domains
      create_list(:domain, 100, dns: nil)
      
      # Queue all available domains
      available = Domain.needing_service('domain_testing')
      Sidekiq::Testing.fake!
      available.each { |d| DomainDnsTestingWorker.perform_async(d.id) }
      
      # Mock Sidekiq queue
      mock_all_queues({
        'domain_dns_testing' => 100,
        'domain_mx_testing' => 0,
        'domain_a_record_testing' => 0,
        'default' => 0
      })
      
      # Initial stats
      stats = controller.send(:get_queue_stats)
      queue_size = stats['domain_dns_testing']
      domains_needing = stats[:domains_needing][:domain_testing]
      
      expect(queue_size).to eq(100)
      expect(domains_needing).to eq(100)
      
      # Mock the service to process domains
      allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
        domain = service.instance_variable_get(:@domain)
        domain.update!(dns: true)
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
      
      # Simulate rapid processing
      processed_count = 0
      available.find_each do |domain|
        DomainDnsTestingWorker.new.perform(domain.id)
        processed_count += 1
        
        # Check stats periodically
        if processed_count % 10 == 0
          # Mock queue size to reflect processed count
          mock_all_queues({
            'domain_dns_testing' => 100 - processed_count,
            'domain_mx_testing' => 0,
            'domain_a_record_testing' => 0,
            'default' => 0
          })
          
          stats = controller.send(:get_queue_stats)
          current_queue_size = stats['domain_dns_testing']
          current_needing = stats[:domains_needing][:domain_testing]
          
          # Queue should decrease
          expect(current_queue_size).to eq(100 - processed_count)
          # Domains needing should also decrease
          expect(current_needing).to eq(100 - processed_count)
        end
        
        break if processed_count >= 100
      end
      
      # Final verification
      stats = controller.send(:get_queue_stats)
      expect(stats['domain_dns_testing']).to eq(0)
      expect(stats[:domains_needing][:domain_testing]).to eq(0)
    end
    
    it 'handles cascading queue effects properly' do
      # Create domains that will trigger follow-up tests
      domains = create_list(:domain, 20, dns: nil, mx: nil, www: nil)
      
      # Track all queue sizes
      initial_stats = controller.send(:get_queue_stats)
      
      # Queue DNS tests
      Sidekiq::Testing.fake! do
        domains.each { |d| DomainDnsTestingWorker.perform_async(d.id) }
      end
      
      # Mock the service to process DNS and queue follow-ups
      allow_any_instance_of(DomainTestingService).to receive(:call) do |service|
        domain = service.instance_variable_get(:@domain)
        domain.update!(dns: true)
        # The real service queues follow-up jobs
        DomainMxTestingWorker.perform_async(domain.id)
        DomainARecordTestingWorker.perform_async(domain.id)
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
      
      # Process DNS tests (should trigger MX and A record tests)
      DomainDnsTestingWorker.jobs.each do |job|
        DomainDnsTestingWorker.new.perform(job['args'].first)
      end
      DomainDnsTestingWorker.clear
      
      # Mock the queue sizes for stats
      mock_all_queues({
        'domain_dns_testing' => 0,
        'domain_mx_testing' => DomainMxTestingWorker.jobs.size,
        'domain_a_record_testing' => 0,
        'default' => DomainARecordTestingWorker.jobs.size
      }, default_a_record_count: DomainARecordTestingWorker.jobs.size)
      
      # Check cascading effects
      stats = controller.send(:get_queue_stats)
      
      # DNS queue should be empty
      expect(stats['domain_dns_testing']).to eq(0)
      expect(stats[:domains_needing][:domain_testing]).to eq(0)
      
      # MX and A record queues should have jobs
      expect(stats['domain_mx_testing']).to eq(20)
      expect(stats['DomainARecordTestingService']).to eq(20)
      
      # Domains should now need MX and A record testing
      expect(stats[:domains_needing][:domain_mx_testing]).to eq(20)
      expect(stats[:domains_needing][:domain_a_record_testing]).to eq(20)
    end
  end
  
  describe 'Real-time Updates During Processing' do
    let(:controller) { DomainsController.new }
    let(:user) { create(:user) }
    
    before do
      allow(controller).to receive(:current_user).and_return(user)
    end
    
    it 'provides accurate counts during rapid processing' do
      # Create many domains
      create_list(:domain, 200, dns: nil)
      
      # Queue them all
      queue_thread = Thread.new do
        Domain.needing_service('domain_testing').find_each do |domain|
          DomainDnsTestingWorker.perform_async(domain.id)
          sleep 0.001 # Slight delay to simulate real queueing
        end
      end
      
      # Monitor stats during processing
      stats_snapshots = []
      monitor_thread = Thread.new do
        10.times do
          sleep 0.1
          stats = controller.send(:get_queue_stats)
          stats_snapshots << {
            time: Time.current,
            queue_size: stats['domain_dns_testing'],
            domains_needing: stats[:domains_needing][:domain_testing],
            processed: Domain.where.not(dns: nil).count
          }
        end
      end
      
      # Process domains
      process_thread = Thread.new do
        sleep 0.2 # Let some queueing happen first
        Sidekiq::Testing.inline! do
          100.times do
            job = Sidekiq::Queue.new('domain_dns_testing').first
            break unless job
            DomainDnsTestingWorker.new.perform(job.args.first)
            job.delete
            sleep 0.002 # Simulate processing time
          end
        end
      end
      
      # Wait for all threads
      [queue_thread, monitor_thread, process_thread].each(&:join)
      
      # Verify stats consistency
      stats_snapshots.each_with_index do |snapshot, i|
        if i > 0
          prev = stats_snapshots[i - 1]
          
          # Queue size should decrease or stay same
          expect(snapshot[:queue_size]).to be <= prev[:queue_size]
          
          # Processed count should increase or stay same
          expect(snapshot[:processed]).to be >= prev[:processed]
          
          # Domains needing + processed should equal total
          total_domains = 200
          expect(snapshot[:domains_needing] + snapshot[:processed]).to be_within(5).of(total_domains)
        end
      end
    end
  end
  
  describe 'Edge Cases and Race Conditions' do
    let(:controller) { DomainsController.new }
    let(:user) { create(:user) }
    
    before do
      allow(controller).to receive(:current_user).and_return(user)
    end
    
    it 'handles simultaneous queueing and processing' do
      create_list(:domain, 50, dns: nil)
      
      errors = []
      
      # Queue domains in one thread
      queue_thread = Thread.new do
        begin
          Domain.needing_service('domain_testing').find_each do |domain|
            DomainDnsTestingWorker.perform_async(domain.id)
            sleep 0.01
          end
        rescue => e
          errors << e
        end
      end
      
      # Process domains in another thread
      process_thread = Thread.new do
        begin
          Sidekiq::Testing.inline! do
            20.times do
              sleep 0.02
              job = Sidekiq::Queue.new('domain_dns_testing').first
              next unless job
              DomainDnsTestingWorker.new.perform(job.args.first)
              job.delete
            end
          end
        rescue => e
          errors << e
        end
      end
      
      # Check stats in third thread
      stats_thread = Thread.new do
        begin
          5.times do
            sleep 0.05
            stats = controller.send(:get_queue_stats)
            
            # Basic sanity checks
            expect(stats['domain_dns_testing']).to be >= 0
            expect(stats[:domains_needing][:domain_testing]).to be >= 0
          end
        rescue => e
          errors << e
        end
      end
      
      [queue_thread, process_thread, stats_thread].each(&:join)
      
      expect(errors).to be_empty
    end
    
    it 'handles domain state changes during processing' do
      domain = create(:domain, dns: nil)
      
      # Queue the domain
      DomainDnsTestingWorker.perform_async(domain.id)
      
      # Change domain state before processing
      domain.update!(dns: true)
      
      # Process the queued job
      Sidekiq::Testing.inline! do
        DomainDnsTestingWorker.drain
      end
      
      # Should handle gracefully
      domain.reload
      expect(domain.dns).to be true
      
      # Check audit logs
      audit_log = ServiceAuditLog.last
      expect(audit_log).to be_present
    end
  end
end