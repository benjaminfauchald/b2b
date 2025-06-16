require 'rails_helper'

RSpec.describe ServiceAuditable, type: :model do
  let(:service_name) { 'domain_testing' }
  let!(:service_config) do
    create(:service_configuration, 
           service_name: service_name,
           refresh_interval_hours: 24,
           batch_size: 100,
           active: true)
  end

  describe 'associations' do
    it { should have_many(:service_audit_logs) }
  end

  describe 'callbacks' do
    context 'when audit is enabled' do
      before do
        allow_any_instance_of(described_class).to receive(:audit_enabled?).and_return(true)
      end

      it 'audits creation' do
        expect {
          create(:domain)
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('automatic_audit')
        expect(audit_log.action).to eq('create')
      end

      it 'audits updates' do
        domain = create(:domain)
        expect {
          domain.update!(name: 'Updated Name')
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('automatic_audit')
        expect(audit_log.action).to eq('update')
        expect(audit_log.changed_fields).to include('name')
      end
    end

    context 'when audit is disabled' do
      before do
        allow_any_instance_of(described_class).to receive(:audit_enabled?).and_return(false)
      end

      it 'does not audit creation' do
        expect {
          create(:domain)
        }.not_to change(ServiceAuditLog, :count)
      end

      it 'does not audit updates' do
        domain = create(:domain)
        expect {
          domain.update!(name: 'Updated Name')
        }.not_to change(ServiceAuditLog, :count)
      end
    end
  end

  describe 'instance methods' do
    describe '#audit_service_operation' do
      let(:domain) { create(:domain) }

      it 'creates audit log and yields with it' do
        expect {
          domain.audit_service_operation(service_name, action: 'test_dns') do |audit_log|
            expect(audit_log).to be_a(ServiceAuditLog)
            expect(audit_log.service_name).to eq(service_name)
            expect(audit_log.action).to eq('test_dns')
            expect(audit_log.auditable).to eq(domain)
          end
        }.to change(ServiceAuditLog, :count).by(1)
      end

      it 'creates audit log with default action' do
        expect {
          domain.audit_service_operation(service_name) do |audit_log|
            expect(audit_log.action).to eq('process')
          end
        }.to change(ServiceAuditLog, :count).by(1)
      end

      it 'returns result from block' do
        result = domain.audit_service_operation(service_name) do |audit_log|
          'test result'
        end
        expect(result).to eq('test result')
      end
    end

    describe '#needs_service?' do
      let(:domain) { create(:domain) }

      it 'returns true when no successful run exists' do
        expect(domain.needs_service?(service_name)).to be true
      end

      it 'returns false when successful run exists within refresh interval' do
        create(:service_audit_log, :success, 
               auditable: domain, 
               service_name: service_name, 
               completed_at: 1.hour.ago)
        expect(domain.needs_service?(service_name)).to be false
      end

      it 'returns true when last successful run is older than refresh interval' do
        create(:service_audit_log, :success, 
               auditable: domain, 
               service_name: service_name, 
               completed_at: 25.hours.ago)
        expect(domain.needs_service?(service_name)).to be true
      end
    end

    describe '#last_service_run' do
      let(:domain) { create(:domain) }

      it 'returns the most recent successful run' do
        old_log = create(:service_audit_log, :success, 
                        auditable: domain, 
                        service_name: service_name, 
                        completed_at: 2.hours.ago)
        new_log = create(:service_audit_log, :success, 
                        auditable: domain, 
                        service_name: service_name, 
                        completed_at: 1.hour.ago)
        create(:service_audit_log, :failed, 
               auditable: domain, 
               service_name: service_name, 
               completed_at: 30.minutes.ago)

        expect(domain.last_service_run(service_name)).to eq(new_log)
      end
    end

    describe '#audit_enabled?' do
      it 'returns true by default' do
        domain = create(:domain)
        expect(domain.audit_enabled?).to be true
      end

      context 'when Rails configuration disables auditing' do
        before do
          allow(Rails.configuration).to receive(:respond_to?).with(:service_auditing_enabled).and_return(true)
          allow(Rails.configuration).to receive(:service_auditing_enabled).and_return(false)
        end

        it 'returns false' do
          domain = create(:domain)
          expect(domain.audit_enabled?).to be false
        end
      end
    end
  end

  describe 'class methods' do
    describe '.with_service_audit' do
      it 'processes records with audit logging' do
        domains = create_list(:domain, 3)
        processed = []

        Domain.with_service_audit(service_name, action: 'test_dns') do |domain, audit_log|
          processed << domain
          expect(audit_log).to be_a(ServiceAuditLog)
          expect(audit_log.service_name).to eq(service_name)
          expect(audit_log.action).to eq('test_dns')
        end

        expect(processed).to match_array(domains)
        expect(ServiceAuditLog.count).to eq(3)
      end

      it 'processes records with default action' do
        domains = create_list(:domain, 3)
        processed = []

        Domain.with_service_audit(service_name) do |domain, audit_log|
          processed << domain
          expect(audit_log.action).to eq('process')
        end

        expect(processed).to match_array(domains)
        expect(ServiceAuditLog.count).to eq(3)
      end
    end

    describe '.needing_service' do
      let!(:domain1) { create(:domain) }
      let!(:domain2) { create(:domain) }
      let!(:domain3) { create(:domain) }

      before do
        create(:service_audit_log, :success, 
               auditable: domain2, 
               service_name: service_name, 
               completed_at: 1.hour.ago)
        create(:service_audit_log, :success, 
               auditable: domain3, 
               service_name: service_name, 
               completed_at: 25.hours.ago)
      end

      it 'returns domains needing service' do
        needing_domains = Domain.needing_service(service_name)
        expect(needing_domains).to include(domain1, domain3)
        expect(needing_domains).not_to include(domain2)
      end
    end
  end

  describe 'private methods' do
    describe '#audit_creation' do
      it 'creates audit log for creation' do
        expect {
          create(:domain)
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('automatic_audit')
        expect(audit_log.action).to eq('create')
      end
    end

    describe '#audit_update' do
      let(:domain) { create(:domain) }

      it 'creates audit log for update with changed fields' do
        expect {
          domain.update!(name: 'Updated Name')
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('automatic_audit')
        expect(audit_log.action).to eq('update')
        expect(audit_log.changed_fields).to include('name')
      end
    end
  end
end 