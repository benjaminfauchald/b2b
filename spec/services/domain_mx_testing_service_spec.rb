# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainMxTestingService, type: :service do
  let(:domain) { create(:domain, domain: 'example.com', dns: true, mx: nil) }
  let(:service) { described_class.new(domain: domain) }

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        create(:service_configuration, service_name: 'domain_mx_testing', active: true)
      end

      context 'when testing single domain' do
        context 'with successful MX resolution' do
          before do
            # Mock successful MX resolution
            resolver_double = double('Resolv::DNS')
            allow(resolver_double).to receive(:getresources).and_return([ double(exchange: 'mail.example.com') ])
            allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
          end

          it 'creates a successful audit log' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_mx_testing')
            expect(audit_log.operation_type).to eq('test_mx')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(domain)
            expect(audit_log.execution_time_ms).to be_present
          end

          it 'includes metadata about the MX test' do
            result = service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['domain_name']).to eq('example.com')
            expect(audit_log.metadata['mx_status']).to eq(true)
            expect(audit_log.metadata['test_duration_ms']).to be_present
          end

          it 'returns successful result' do
            result = service.perform

            expect(result.success?).to be true
            expect(result.message).to eq('MX test completed')
            expect(result.data[:result][:status]).to eq('success')
          end

          it 'updates domain MX status to true' do
            service.perform
            domain.reload

            expect(domain.mx).to be true
          end

          it 'tracks execution time in audit log' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.execution_time_ms).to be > 0
            expect(audit_log.started_at).to be_present
            expect(audit_log.completed_at).to be_present
          end
        end

        context 'with no MX records found' do
          before do
            # Mock no MX records
            resolver_double = double('Resolv::DNS')
            allow(resolver_double).to receive(:getresources).and_return([])
            allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
          end

          it 'creates audit log with successful status but no_records result' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_mx_testing')
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['mx_status']).to eq(false)
          end

          it 'updates domain MX status to false' do
            service.perform
            domain.reload

            expect(domain.mx).to be false
          end
        end

        context 'with MX resolution error' do
          before do
            # Mock MX resolution error
            resolver_double = double('Resolv::DNS')
            allow(resolver_double).to receive(:getresources).and_raise(Resolv::ResolvError)
            allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
          end

          it 'creates audit log with successful status but error result' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('domain_mx_testing')
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['mx_status']).to eq(false)
          end

          it 'updates domain MX status to false' do
            service.perform
            domain.reload

            expect(domain.mx).to be false
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
            expect(audit_log.metadata['mx_status']).to eq(false)
          end

          it 'returns successful result with error status in data' do
            result = service.perform

            expect(result.success?).to be true
            expect(result.data[:result][:status]).to eq('error')
          end
        end
      end

      context 'when testing domains in batches' do
        let!(:domains) { create_list(:domain, 3, dns: true, mx: nil) }
        let(:service) { described_class.new }

        before do
          # Mock successful MX resolution for all domains
          resolver_double = double('Resolv::DNS')
          allow(resolver_double).to receive(:getresources).and_return([ double(exchange: 'mail.example.com') ])
          allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
        end

        it 'creates audit logs for each domain' do
          expect { service.perform }.to change(ServiceAuditLog, :count).by(3) # 3 domains

          audit_logs = ServiceAuditLog.where(service_name: 'domain_mx_testing')
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

        it 'updates all domain MX statuses' do
          service.perform

          domains.each(&:reload)
          expect(domains.all? { |d| d.mx == true }).to be true
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        create(:service_configuration, service_name: 'domain_mx_testing', active: false)
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

  describe '#check_mx_record' do
    it 'returns true when MX records exist' do
      resolver_double = double('Resolv::DNS')
      allow(resolver_double).to receive(:getresources).and_return([ double(exchange: 'mail.example.com') ])
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)

      result = service.send(:check_mx_record, 'example.com')
      expect(result).to be true
    end

    it 'returns false when no MX records exist' do
      resolver_double = double('Resolv::DNS')
      allow(resolver_double).to receive(:getresources).and_return([])
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)

      result = service.send(:check_mx_record, 'example.com')
      expect(result).to be false
    end

    it 'returns false on timeout' do
      resolver_double = double('Resolv::DNS')
      allow(resolver_double).to receive(:getresources).and_raise(Timeout::Error)
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)

      result = service.send(:check_mx_record, 'example.com')
      expect(result).to be false
    end

    it 'returns false on DNS resolution error' do
      resolver_double = double('Resolv::DNS')
      allow(resolver_double).to receive(:getresources).and_raise(Resolv::ResolvError)
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)

      result = service.send(:check_mx_record, 'example.com')
      expect(result).to be false
    end

    it 'returns false on standard error' do
      resolver_double = double('Resolv::DNS')
      allow(resolver_double).to receive(:getresources).and_raise(StandardError)
      allow(Resolv::DNS).to receive(:new).and_return(resolver_double)

      result = service.send(:check_mx_record, 'example.com')
      expect(result).to be false
    end
  end

  describe 'legacy class methods' do
    describe '.test_mx' do
      it 'maintains backward compatibility' do
        # Mock successful MX resolution
        service_double = double('DomainMxTestingService')
        allow(service_double).to receive(:perform_mx_test).and_return({ status: 'success' })
        allow(described_class).to receive(:new).and_return(service_double)

        result = described_class.test_mx(domain)
        expect(result).to be true
      end

      it 'handles MX resolution failures' do
        # Mock MX resolution failure
        service_double = double('DomainMxTestingService')
        allow(service_double).to receive(:perform_mx_test).and_return({ status: 'error' })
        allow(described_class).to receive(:new).and_return(service_double)

        result = described_class.test_mx(domain)
        expect(result).to be false
      end
    end

    describe '.queue_all_domains' do
      before do
        create_list(:domain, 5, dns: true, mx: nil)
        allow(DomainMxTestingWorker).to receive(:perform_async)
      end

      it 'queues all domains needing testing' do
        count = described_class.queue_all_domains

        expect(count).to eq(5)
        expect(DomainMxTestingWorker).to have_received(:perform_async).exactly(5).times
      end
    end

    describe '.queue_100_domains' do
      before do
        create_list(:domain, 150, dns: true, mx: nil)
        allow(DomainMxTestingWorker).to receive(:perform_async)
      end

      it 'queues only 100 domains' do
        count = described_class.queue_100_domains

        expect(count).to eq(100)
        expect(DomainMxTestingWorker).to have_received(:perform_async).exactly(100).times
      end
    end
  end
end
