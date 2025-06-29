# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe DomainDnsTestingWorker, type: :worker do
  let(:domain) { create(:domain, dns: nil) }
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
          allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([ 'fake_record' ])
        end

        it 'updates domain DNS status to true' do
          worker.perform(domain.id)

          domain.reload
          expect(domain.dns).to be true
        end

        it 'creates a service audit log' do
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
          allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([])
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
          allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
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

      # Mock DNS resolution
      allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([ 'fake_record' ])

      # Process concurrently
      Sidekiq::Testing.inline! do
        threads = domains.map do |domain|
          Thread.new { described_class.perform_async(domain.id) }
        end
        threads.each(&:join)
      end

      # All domains should be processed
      domains.each(&:reload)
      expect(domains.all? { |d| d.dns == true }).to be true
    end
  end

  describe 'Error handling and retries' do
    it 'retries on transient failures' do
      call_count = 0

      # Mock failure then success
      allow_any_instance_of(DomainTestingService).to receive(:perform) do
        call_count += 1
        if call_count == 1
          raise StandardError, 'Temporary failure'
        else
          OpenStruct.new(success?: true)
        end
      end

      # Should retry and eventually succeed
      expect {
        Sidekiq::Testing.inline! do
          described_class.perform_async(domain.id)
        end
      }.not_to raise_error
    end

    it 'dead letters after max retries' do
      # Force failures
      allow_any_instance_of(DomainTestingService).to receive(:perform)
        .and_raise(StandardError, 'Persistent failure')

      Sidekiq::Testing.fake! do
        described_class.perform_async(domain.id)

        # Simulate retries
        expect {
          3.times do
            begin
              described_class.drain
            rescue StandardError
              # Expected
            end
          end
        }.to raise_error(StandardError, 'Persistent failure')
      end
    end
  end

  describe 'Performance characteristics' do
    it 'processes domains quickly' do
      # Mock fast DNS resolution
      allow_any_instance_of(Resolv::DNS).to receive(:getresources) do
        sleep 0.01 # Simulate minimal network delay
        [ 'fake_record' ]
      end

      start_time = Time.current

      worker.perform(domain.id)

      processing_time = Time.current - start_time

      # Should complete quickly
      expect(processing_time).to be < 0.1.seconds
    end

    it 'handles batch processing efficiently' do
      domains = create_list(:domain, 50, dns: nil)

      # Mock DNS resolution
      allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([ 'fake_record' ])

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
