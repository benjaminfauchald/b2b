# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainTestingService, type: :service do
  let(:company) { create(:company) }
  let(:domain) { create(:domain, dns: nil, mx: nil, www: nil) }
  let(:service) { described_class.new(domain: domain) }

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        create(:service_configuration, service_name: 'domain_testing', active: true)
      end

      context 'when testing single domain' do
        context 'with successful DNS resolution' do
          before do
            # Mock successful DNS resolution with proper DNS resource objects
            a_record = double('A Record', address: '192.168.1.1')
            mx_record = double('MX Record', exchange: "mail.#{domain.domain}")
            txt_record = double('TXT Record', strings: [ 'v=spf1 -all' ])

            allow_any_instance_of(Resolv::DNS).to receive(:getresources).with(domain.domain, Resolv::DNS::Resource::IN::A).and_return([ a_record ])
            allow_any_instance_of(Resolv::DNS).to receive(:getresources).with(domain.domain, Resolv::DNS::Resource::IN::MX).and_return([ mx_record ])
            allow_any_instance_of(Resolv::DNS).to receive(:getresources).with(domain.domain, Resolv::DNS::Resource::IN::TXT).and_return([ txt_record ])

            # Mock worker classes
            stub_const('DomainMxTestingWorker', Class.new do
              def self.perform_async(domain_id); end
            end)
            stub_const('DomainARecordTestingWorker', Class.new do
              def self.perform_async(domain_id); end
            end)
          end

          it 'creates a successful audit log' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_testing')
            expect(audit_log.operation_type).to eq('test_dns')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(domain)
            expect(audit_log.execution_time_ms).to be_present
          end

          it 'includes metadata about the DNS test' do
            result = service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['domain_name']).to eq(domain.domain)
            expect(audit_log.metadata['dns_status']).to eq(true)
            expect(audit_log.metadata['test_result']).to eq('success')
          end

          it 'returns successful result' do
            result = service.perform

            expect(result.success?).to be true
            expect(result.message).to eq('DNS test completed')
            expect(result.data[:result][:status]).to eq('success')
          end

          it 'updates domain DNS status to true' do
            service.perform
            domain.reload

            expect(domain.dns).to be true
          end

          it 'tracks execution time in audit log' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.execution_time_ms).to be > 0
            expect(audit_log.started_at).to be_present
            expect(audit_log.completed_at).to be_present
          end

          it 'queues follow-up tests for successful DNS' do
            expect(DomainMxTestingWorker).to receive(:perform_async).with(domain.id).once
            expect(DomainARecordTestingWorker).to receive(:perform_async).with(domain.id).once

            service.perform
          end
        end

        context 'with DNS resolution failure' do
          before do
            # Mock DNS resolution failure
            allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([])
          end

          it 'creates audit log with successful status but no_records result' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_testing')
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['test_result']).to eq('no_records')
          end

          it 'updates domain DNS status to false' do
            service.perform
            domain.reload

            expect(domain.dns).to be false
          end

          it 'does not queue follow-up tests' do
            expect(DomainMxTestingWorker).not_to receive(:perform_async)
            expect(DomainARecordTestingWorker).not_to receive(:perform_async)

            service.perform
          end
        end

        context 'with DNS resolution error' do
          before do
            # Mock DNS resolution error
            allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_raise(Resolv::ResolvError)
          end

          it 'creates audit log with successful status but error result' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_testing')
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['test_result']).to eq('error')
          end

          it 'updates domain DNS status to false' do
            service.perform
            domain.reload

            expect(domain.dns).to be false
          end
        end

        context 'with timeout error' do
          before do
            # Mock timeout error in DNS resolution
            allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_raise(Timeout::Error)
          end

          it 'creates audit log with success status but error metadata' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['test_result']).to eq('error')
            expect(audit_log.metadata['dns_status']).to eq(false)
          end

          it 'returns successful result with error status in data' do
            result = service.perform

            expect(result.success?).to be true
            expect(result.data[:result][:status]).to eq('error')
            expect(result.data[:result][:records][:error]).to include('timed out')
          end
        end
      end

      context 'when testing domains in batches' do
        let!(:domains) { create_list(:domain, 3, dns: nil) }
        let(:service) { described_class.new }

        before do
          # Mock successful DNS resolution for all domains
          a_record = double('A Record', address: '192.168.1.1')
          mx_record = double('MX Record', exchange: 'mail.example.com')
          txt_record = double('TXT Record', strings: [ 'v=spf1 -all' ])

          allow_any_instance_of(Resolv::DNS).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::A).and_return([ a_record ])
          allow_any_instance_of(Resolv::DNS).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::MX).and_return([ mx_record ])
          allow_any_instance_of(Resolv::DNS).to receive(:getresources).with(anything, Resolv::DNS::Resource::IN::TXT).and_return([ txt_record ])

          # Mock worker classes
          stub_const('DomainMxTestingWorker', Class.new do
            def self.perform_async(domain_id); end
          end)
          stub_const('DomainARecordTestingWorker', Class.new do
            def self.perform_async(domain_id); end
          end)
        end

        it 'creates audit logs for each domain' do
          expect { service.perform }.to change(ServiceAuditLog, :count).by(3) # 3 domains

          audit_logs = ServiceAuditLog.where(service_name: 'domain_testing')
          domain_logs = audit_logs.where.not(auditable: nil)
          expect(domain_logs.count).to eq(3)
          expect(domain_logs.all? { |log| log.status == 'success' }).to be true
        end

        it 'processes all domains needing testing' do
          result = service.perform

          expect(result.success?).to be true
          expect(result.data[:processed]).to eq(3)
          expect(result.data[:successful]).to eq(3)
          expect(result.data[:failed]).to eq(0)
          expect(result.data[:errors]).to eq(0)
        end

        it 'updates all domain DNS statuses' do
          service.perform

          domains.each(&:reload)
          expect(domains.all? { |d| d.dns == true }).to be true
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        create(:service_configuration, service_name: 'domain_testing', active: false)
      end

      it 'does not perform testing' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to eq('Service is disabled')
      end

      it 'does not create audit log' do
        expect { service.perform }.not_to change(ServiceAuditLog, :count)
      end
    end
  end

  describe 'legacy class methods' do
    describe '.test_dns' do
      it 'maintains backward compatibility' do
        # Mock DNS resolution
        allow(Resolv::DNS).to receive(:open).and_yield(double(getaddress: '1.2.3.4'))

        result = described_class.test_dns(domain)
        domain.reload

        expect(result).to be true
        expect(domain.dns).to be true
      end

      it 'handles DNS resolution failures' do
        # Mock DNS resolution failure
        allow(Resolv::DNS).to receive(:open).and_raise(Resolv::ResolvError)

        result = described_class.test_dns(domain)
        domain.reload

        expect(result).to be false
        expect(domain.dns).to be false
      end
    end

    describe '.queue_all_domains' do
      before do
        create_list(:domain, 5, dns: nil)
        allow(DomainTestJob).to receive(:perform_later)
      end

      it 'queues all domains needing testing' do
        count = described_class.queue_all_domains

        expect(count).to eq(5)
        expect(DomainTestJob).to have_received(:perform_later).exactly(5).times
      end
    end

    describe '.queue_100_domains' do
      before do
        create_list(:domain, 150, dns: nil)
        allow(DomainTestJob).to receive(:perform_later)
      end

      it 'queues only 100 domains' do
        count = described_class.queue_100_domains

        expect(count).to eq(100)
        expect(DomainTestJob).to have_received(:perform_later).exactly(100).times
      end
    end
  end

  describe '#has_dns?' do
    it 'returns true for domains with A records' do
      allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([ 'fake_record' ])

      result = service.send(:has_dns?, domain.domain)
      expect(result).to be true
    end

    it 'returns false for domains without A records' do
      allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_return([])

      result = service.send(:has_dns?, 'nonexistent.invalid')
      expect(result).to be false
    end

    it 'returns false on timeout' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      result = service.send(:has_dns?, 'slow-domain.com')
      expect(result).to be false
    end

    it 'returns false on DNS resolution error' do
      allow_any_instance_of(Resolv::DNS).to receive(:getresources).and_raise(Resolv::ResolvError)

      result = service.send(:has_dns?, 'error-domain.com')
      expect(result).to be false
    end
  end
end
