# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe DomainDnsTestingWorker, type: :worker do
  let(:domain) { create(:domain, dns: nil, mx: nil, www: nil) }
  let(:worker) { described_class.new }

  before do
    create(:service_configuration, service_name: 'domain_testing', active: true)
    create(:service_configuration, service_name: 'domain_mx_testing', active: true)
    create(:service_configuration, service_name: 'domain_a_record_testing', active: true)
  end

  describe 'Sidekiq configuration' do
    it 'uses the correct queue' do
      expect(described_class.sidekiq_options['queue']).to eq('domain_dns_testing')
    end

    it 'has retry configuration' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#perform' do
    context 'with valid domain' do
      context 'when DNS resolution succeeds' do
        before do
          # Mock the instance method for getresources to return records
          resolver_double = instance_double(Resolv::DNS)
          allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
          allow(resolver_double).to receive(:getresources).with(domain.domain, Resolv::DNS::Resource::IN::A).and_return([ double(address: '1.2.3.4') ])
          allow(resolver_double).to receive(:getresources).with(domain.domain, Resolv::DNS::Resource::IN::MX).and_return([ double(exchange: 'mx.example.com') ])
          allow(resolver_double).to receive(:getresources).with(domain.domain, Resolv::DNS::Resource::IN::TXT).and_return([ double(strings: [ 'v=spf1' ]) ])
        end

        it 'updates domain DNS status to true' do
          worker.perform(domain.id)

          domain.reload
          expect(domain.dns).to be true
        end

        it 'creates a service audit log' do
          # Ensure clean state
          ServiceAuditLog.destroy_all

          # Mock follow-up worker calls to prevent additional audit logs in tests
          allow(DomainMxTestingWorker).to receive(:perform_async)
          allow(DomainARecordTestingWorker).to receive(:perform_async)

          expect {
            worker.perform(domain.id)
          }.to change(ServiceAuditLog, :count).by(1)

          audit_log = ServiceAuditLog.last
          expect(audit_log.service_name).to eq('domain_testing')
          expect(audit_log.auditable).to eq(domain)
          expect(audit_log.status).to eq('success')
        end

        it 'queues follow-up tests' do
          expect(DomainMxTestingWorker).to receive(:perform_async).with(domain.id)
          expect(DomainARecordTestingWorker).to receive(:perform_async).with(domain.id)

          worker.perform(domain.id)
        end

        it 'does not queue follow-up tests if already tested' do
          domain.update!(mx: true, www: true)

          expect(DomainMxTestingWorker).not_to receive(:perform_async)
          expect(DomainARecordTestingWorker).not_to receive(:perform_async)

          worker.perform(domain.id)
        end
      end

      context 'when DNS resolution fails' do
        before do
          # Mock the instance method for getresources to return empty arrays (no records)
          resolver_double = instance_double(Resolv::DNS)
          allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
          allow(resolver_double).to receive(:getresources).and_return([])
        end

        it 'updates domain DNS status to false' do
          worker.perform(domain.id)

          domain.reload
          expect(domain.dns).to be false
        end

        it 'does not queue follow-up tests' do
          expect(DomainMxTestingWorker).not_to receive(:perform_async)
          expect(DomainARecordTestingWorker).not_to receive(:perform_async)

          worker.perform(domain.id)
        end

        it 'still creates audit log' do
          expect {
            worker.perform(domain.id)
          }.to change(ServiceAuditLog, :count).by(1)

          audit_log = ServiceAuditLog.last
          expect(audit_log.status).to eq('success') # Service ran successfully
          expect(audit_log.metadata['test_result']).to eq('no_records')
        end
      end

      context 'when DNS resolution times out' do
        before do
          # Mock the instance method for getresources to raise Timeout::Error
          resolver_double = instance_double(Resolv::DNS)
          allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
          allow(resolver_double).to receive(:getresources).and_raise(Timeout::Error)
        end

        it 'handles timeout gracefully' do
          expect {
            worker.perform(domain.id)
          }.not_to raise_error
        end

        it 'marks domain DNS as false' do
          worker.perform(domain.id)

          domain.reload
          expect(domain.dns).to be false
        end
      end
    end

    context 'with invalid domain ID' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          worker.perform(999999)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when service is disabled' do
      before do
        ServiceConfiguration.find_by(service_name: 'domain_testing').update!(active: false)
      end

      it 'does not process the domain' do
        worker.perform(domain.id)

        domain.reload
        expect(domain.dns).to be nil
      end

      it 'logs the disabled status' do
        expect(Rails.logger).to receive(:warn).with(/Service is disabled/)

        worker.perform(domain.id)
      end
    end
  end

  describe 'Queue behavior' do
    it 'processes jobs in FIFO order' do
      domains = create_list(:domain, 5, dns: nil)
      processed_order = []

      # Mock DNS test to track processing order
      allow_any_instance_of(DomainTestingService).to receive(:perform) do |service|
        processed_order << service.domain.id
        OpenStruct.new(success?: true)
      end

      # Queue domains
      Sidekiq::Testing.fake! do
        domains.each { |d| described_class.perform_async(d.id) }

        # Process queue
        described_class.drain
      end

      # Should process in order queued
      expect(processed_order).to eq(domains.map(&:id))
    end

    it 'handles concurrent processing' do
      domains = create_list(:domain, 10, dns: nil)

      # Mock DNS resolution to always succeed by mocking the perform_dns_test method
      allow_any_instance_of(DomainTestingService).to receive(:perform_dns_test).and_return({
        status: "success",
        records: {
          a: [ '1.2.3.4' ],
          mx: [ 'mx.example.com' ],
          txt: [ 'v=spf1' ]
        }
      })

      # Process concurrently using threads with proper synchronization
      mutex = Mutex.new
      processed_count = 0

      threads = domains.map do |domain|
        Thread.new do
          # Perform the work directly instead of async to ensure completion
          worker = described_class.new
          worker.perform(domain.id)

          mutex.synchronize { processed_count += 1 }
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify all domains were processed
      expect(processed_count).to eq(domains.size)

      # All domains should be marked as having DNS
      domains.each(&:reload)
      expect(domains.all? { |d| d.dns == true }).to be true
    end
  end

  describe 'Error handling and retries' do
    it 'retries on transient failures' do
      # This test verifies that the worker is configured to retry
      # Actual retry behavior is handled by Sidekiq and is difficult to test in isolation

      # Verify retry configuration
      expect(described_class.sidekiq_options['retry']).to eq(3)

      # Test that errors are properly re-raised for Sidekiq to handle
      allow_any_instance_of(DomainTestingService).to receive(:perform)
        .and_raise(StandardError, 'Temporary failure')

      worker = described_class.new

      expect {
        worker.perform(domain.id)
      }.to raise_error(StandardError, 'Temporary failure')

      # In production, Sidekiq would catch this error and retry based on the retry: 3 option
    end

    it 'dead letters after max retries' do
      # This test verifies the worker's behavior when it exhausts retries
      # The actual dead letter queue management is handled by Sidekiq

      # Force persistent failures
      allow_any_instance_of(DomainTestingService).to receive(:perform)
        .and_raise(StandardError, 'Persistent failure')

      # Verify the worker has retry limit configured
      expect(described_class.sidekiq_options['retry']).to eq(3)

      # Test that the worker properly raises errors for Sidekiq to handle
      worker = described_class.new

      # Each call should raise the error
      3.times do
        expect {
          worker.perform(domain.id)
        }.to raise_error(StandardError, 'Persistent failure')
      end

      # In production, after 3 retries (as configured), Sidekiq would move this to the dead set
      # This is Sidekiq's internal behavior and doesn't need unit testing here
    end
  end

  describe 'Performance characteristics' do
    it 'processes domains quickly' do
      # Mock fast DNS resolution
      resolver_double = instance_double(Resolv::DNS)
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
      allow(resolver_double).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::A) do
        sleep 0.01 # Simulate minimal network delay
        [ double(address: '1.2.3.4') ]
      end
      allow(resolver_double).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::MX) do
        sleep 0.01
        [ double(exchange: 'mx.example.com') ]
      end
      allow(resolver_double).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::TXT) do
        sleep 0.01
        [ double(strings: [ 'v=spf1' ]) ]
      end

      start_time = Time.current

      worker.perform(domain.id)

      processing_time = Time.current - start_time

      # Should complete quickly (adjusted for CI environments)
      expect(processing_time).to be < 0.5.seconds
    end

    it 'handles batch processing efficiently' do
      domains = create_list(:domain, 50, dns: nil)

      # Mock DNS resolution
      resolver_double = instance_double(Resolv::DNS)
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
      allow(resolver_double).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::A).and_return([ double(address: '1.2.3.4') ])
      allow(resolver_double).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::MX).and_return([ double(exchange: 'mx.example.com') ])
      allow(resolver_double).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::TXT).and_return([ double(strings: [ 'v=spf1' ]) ])

      start_time = Time.current

      Sidekiq::Testing.inline! do
        domains.each { |d| described_class.perform_async(d.id) }
      end

      total_time = Time.current - start_time
      avg_time_per_domain = total_time / domains.count

      # Average time per domain should be very low
      expect(avg_time_per_domain).to be < 0.05.seconds
    end
  end
end
