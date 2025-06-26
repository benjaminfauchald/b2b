# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainARecordTestingService, type: :service do
  let(:domain) { create(:domain, domain: 'example.com', dns: true, www: nil) }
  let(:service) { described_class.new(domain: domain) }

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        create(:service_configuration, service_name: 'domain_a_record_testing', active: true)
      end

      context 'when testing single domain' do
        context 'with successful A record resolution' do
          before do
            # Mock successful A record resolution
            allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return('192.168.1.1')
          end

          it 'creates a successful audit log' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_a_record_testing')
            expect(audit_log.operation_type).to eq('test_a_record')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(domain)
            expect(audit_log.execution_time_ms).to be_present
          end

          it 'includes metadata about the A record test' do
            result = service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['domain_name']).to eq('example.com')
            expect(audit_log.metadata['www_status']).to eq(true)
            expect(audit_log.metadata['test_result']).to eq(:success)
          end

          it 'returns successful result' do
            result = service.perform

            expect(result.success?).to be true
            expect(result.message).to eq('A record test completed')
            expect(result.data[:result][:status]).to eq(:success)
          end

          it 'updates domain www status to true' do
            service.perform
            domain.reload

            expect(domain.www).to be true
          end

          it 'tracks execution time in audit log' do
            service.perform
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.execution_time_ms).to be > 0
            expect(audit_log.started_at).to be_present
            expect(audit_log.completed_at).to be_present
          end
        end

        context 'with A record resolution failure' do
          before do
            # Mock A record resolution failure
            allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(Resolv::ResolvError)
          end

          it 'creates audit log with successful status but no_records result' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_a_record_testing')
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['test_result']).to eq(:no_records)
          end

          it 'updates domain www status to false' do
            service.perform
            domain.reload

            expect(domain.www).to be false
          end
        end

        context 'with timeout error' do
          before do
            # Mock timeout error
            allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(Timeout::Error)
          end

          it 'creates audit log with successful status but timeout result' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_a_record_testing')
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['test_result']).to eq(:timeout)
          end

          it 'updates domain www status to false' do
            service.perform
            domain.reload

            expect(domain.www).to be false
          end
        end

        context 'with unexpected error during service execution' do
          before do
            # Mock an error in the audit_service_operation itself
            allow_any_instance_of(described_class).to receive(:audit_service_operation).and_raise(StandardError, 'Service error')
          end

          it 'creates audit log with failed status' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('failed')
            expect(audit_log.error_message).to include('Service error')
          end

          it 'returns error result' do
            result = service.perform

            expect(result.success?).to be false
            expect(result.error).to include('Service error')
          end
        end
      end

      context 'when testing domains in batches' do
        let!(:domains) { create_list(:domain, 3, dns: true, www: nil) }
        let(:service) { described_class.new }

        before do
          # Mock successful A record resolution for all domains
          allow(Resolv).to receive(:getaddress).and_return('192.168.1.1')
        end

        it 'creates audit logs for each domain' do
          expect { service.perform }.to change(ServiceAuditLog, :count).by(4) # 3 domains + 1 batch result

          audit_logs = ServiceAuditLog.where(service_name: 'domain_a_record_testing')
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

        it 'updates all domain www statuses' do
          service.perform

          domains.each(&:reload)
          expect(domains.all? { |d| d.www == true }).to be true
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        create(:service_configuration, service_name: 'domain_a_record_testing', active: false)
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
    describe '.test_a_record' do
      it 'maintains backward compatibility for successful resolution' do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return('192.168.1.1')

        result = described_class.test_a_record(domain)
        domain.reload

        expect(result).to be true
        expect(domain.www).to be true
      end

      it 'handles A record resolution failures' do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(Resolv::ResolvError)

        result = described_class.test_a_record(domain)
        domain.reload

        expect(result).to be false
        expect(domain.www).to be false
      end

      it 'handles timeout errors' do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(Timeout::Error)

        result = described_class.test_a_record(domain)
        domain.reload

        expect(result).to be false
        expect(domain.www).to be false
      end

      it 'handles unexpected errors' do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(StandardError, 'Network error')

        result = described_class.test_a_record(domain)
        domain.reload

        expect(result).to be nil
        expect(domain.www).to be nil
      end
    end

    describe '.queue_all_domains' do
      before do
        create_list(:domain, 5, dns: true, www: nil)
        allow(DomainARecordTestingWorker).to receive(:perform_async)
      end

      it 'queues all domains needing testing' do
        count = described_class.queue_all_domains

        expect(count).to eq(5)
        expect(DomainARecordTestingWorker).to have_received(:perform_async).exactly(5).times
      end
    end

    describe '.queue_100_domains' do
      before do
        create_list(:domain, 150, dns: true, www: nil)
        allow(DomainARecordTestingWorker).to receive(:perform_async)
      end

      it 'queues only 100 domains' do
        count = described_class.queue_100_domains

        expect(count).to eq(100)
        expect(DomainARecordTestingWorker).to have_received(:perform_async).exactly(100).times
      end
    end
  end

  describe '#needs_www_testing?' do
    it 'returns true for domains with dns=true and www=nil' do
      test_domain = create(:domain, dns: true, www: nil)
      result = service.send(:needs_www_testing?, test_domain)
      expect(result).to be true
    end

    it 'returns false for domains with dns=false' do
      test_domain = create(:domain, dns: false, www: nil)
      result = service.send(:needs_www_testing?, test_domain)
      expect(result).to be false
    end

    it 'returns false for domains with www already set' do
      test_domain = create(:domain, dns: true, www: true)
      result = service.send(:needs_www_testing?, test_domain)
      expect(result).to be false
    end
  end
end