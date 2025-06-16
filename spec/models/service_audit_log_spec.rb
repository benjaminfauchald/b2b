require 'rails_helper'

RSpec.describe ServiceAuditLog, type: :model do
  let(:service_name) { 'domain_testing' }
  let!(:service_config) do
    create(:service_configuration, 
           service_name: service_name,
           refresh_interval_hours: 24,
           batch_size: 100,
           active: true)
  end

  describe 'associations' do
    it { should belong_to(:auditable) }
  end

  describe 'validations' do
    it { should validate_presence_of(:service_name) }
    it { should validate_presence_of(:action) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:auditable) }
    it { should validate_length_of(:service_name).is_at_most(100) }
    it { should validate_length_of(:action).is_at_most(50) }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(pending: 0, success: 1, failed: 2).with_prefix(true) }
  end

  describe 'scopes' do
    let!(:recent_log) { create(:service_audit_log, created_at: 1.hour.ago) }
    let!(:old_log) { create(:service_audit_log, created_at: 1.week.ago) }
    let!(:user_log) { create(:service_audit_log, service_name: 'user_enhancement_service') }
    let!(:domain_log) { create(:service_audit_log, service_name: 'domain_testing_service') }
    let!(:success_log) { create(:service_audit_log, :success) }
    let!(:failed_log) { create(:service_audit_log, :failed) }

    describe '.recent' do
      it 'orders by created_at desc' do
        # Get only the logs we created for this test
        test_logs = ServiceAuditLog.where(id: [recent_log.id, old_log.id]).recent
        expect(test_logs.to_a).to eq([recent_log, old_log])
      end
    end

    describe '.for_service' do
      let!(:log1) { create(:service_audit_log, service_name: service_name) }
      let!(:log2) { create(:service_audit_log, service_name: 'other_service') }

      it 'returns only logs for specified service' do
        expect(ServiceAuditLog.for_service(service_name)).to include(log1)
        expect(ServiceAuditLog.for_service(service_name)).not_to include(log2)
      end
    end

    describe '.successful' do
      it 'returns only successful logs' do
        expect(ServiceAuditLog.successful).to include(success_log)
        expect(ServiceAuditLog.successful).not_to include(failed_log)
      end
    end

    describe '.failed' do
      it 'returns only failed logs' do
        expect(ServiceAuditLog.failed).to include(failed_log)
        expect(ServiceAuditLog.failed).not_to include(success_log)
      end
    end

    describe '.for_auditable' do
      let(:domain) { create(:domain) }
      let!(:log1) { create(:service_audit_log, auditable: domain) }
      let!(:log2) { create(:service_audit_log) }

      it 'returns only logs for specified auditable' do
        expect(ServiceAuditLog.for_auditable(domain)).to include(log1)
        expect(ServiceAuditLog.for_auditable(domain)).not_to include(log2)
      end
    end
  end

  describe 'instance methods' do
    let(:audit_log) { build(:service_audit_log) }
    let!(:service_config) { create(:service_configuration, service_name: service_name) }

    describe '#mark_started!' do
      it 'sets started_at timestamp' do
        expect { audit_log.mark_started! }.to change { audit_log.started_at }.from(nil)
      end
    end

    describe '#mark_completed!' do
      it 'sets completed_at timestamp and calculates duration' do
        audit_log.started_at = 1.second.ago
        expect { audit_log.mark_completed! }.to change { audit_log.completed_at }.from(nil)
        expect(audit_log.duration_ms).to be > 0
      end
    end

    describe '#mark_success!' do
      let(:log) { create(:service_audit_log, status: :started) }

      it 'marks log as successful' do
        log.mark_success!
        expect(log.status).to eq('success')
        expect(log.completed_at).to be_present
      end
    end

    describe '#mark_failed!' do
      let(:log) { create(:service_audit_log, status: :started) }

      it 'marks log as failed' do
        log.mark_failed!('Test error')
        expect(log.status).to eq('failed')
        expect(log.error_message).to eq('Test error')
        expect(log.completed_at).to be_present
      end
    end

    describe '#add_context' do
      let(:log) { create(:service_audit_log) }

      it 'adds context to log' do
        log.add_context(test_key: 'test_value')
        expect(log.context['test_key']).to eq('test_value')
      end

      it 'merges with existing context' do
        log.update!(context: { existing_key: 'existing_value' })
        log.add_context(new_key: 'new_value')
        expect(log.context).to include(
          'existing_key' => 'existing_value',
          'new_key' => 'new_value'
        )
      end
    end

    describe '#track_changes' do
      let(:user) { create(:user, name: 'John') }
      let(:audit_log) { build(:service_audit_log, auditable: user) }

      it 'tracks changed fields' do
        user.name = 'Jane'
        audit_log.track_changes(user)
        expect(audit_log.changed_fields).to include('name')
      end
    end

    it 'sets service_name' do
      expect(audit_log.service_name).to eq(service_name)
    end

    describe '#status_success?' do
      it 'returns true for success status' do
        log = create(:service_audit_log, :success)
        expect(log.status_success?).to be true
      end

      it 'returns false for other statuses' do
        log = create(:service_audit_log, :failed)
        expect(log.status_success?).to be false
      end
    end

    describe '#status_failed?' do
      it 'returns true for failed status' do
        log = create(:service_audit_log, :failed)
        expect(log.status_failed?).to be true
      end

      it 'returns false for other statuses' do
        log = create(:service_audit_log, :success)
        expect(log.status_failed?).to be false
      end
    end
  end

  describe 'class methods' do
    describe '.batch_audit' do
      let(:users) { create_list(:user, 3) }

      it 'creates audit logs for batch processing' do
        expect do
          ServiceAuditLog.batch_audit(users, service_name: 'test_service') do |user, audit_log|
            audit_log.mark_success!
          end
        end.to change(ServiceAuditLog, :count).by(3)
      end

      it 'yields each record with its audit log' do
        yielded_pairs = []
        ServiceAuditLog.batch_audit(users, service_name: 'test_service') do |user, audit_log|
          yielded_pairs << [user, audit_log]
          audit_log.mark_success!
        end

        expect(yielded_pairs.size).to eq(3)
        yielded_pairs.each do |user, audit_log|
          expect(user).to be_a(User)
          expect(audit_log).to be_a(ServiceAuditLog)
          expect(audit_log.auditable).to eq(user)
        end
      end

      it 'handles errors and marks failed logs' do
        expect do
          ServiceAuditLog.batch_audit(users, service_name: 'test_service') do |user, audit_log|
            raise 'Test error'
          end
        end.to change(ServiceAuditLog, :count).by(3)
      end
    end

    describe '.cleanup_old_logs' do
      let!(:old_logs) { create_list(:service_audit_log, 3, created_at: 100.days.ago) }
      let!(:recent_logs) { create_list(:service_audit_log, 2, created_at: 1.day.ago) }

      it 'removes logs older than specified days' do
        expect { ServiceAuditLog.cleanup_old_logs(90) }.to change(ServiceAuditLog, :count).by(-3)
        expect(ServiceAuditLog.all).to match_array(recent_logs)
      end
    end

    describe '.create_for_service' do
      let(:domain) { create(:domain) }

      it 'creates log with service name and action' do
        log = ServiceAuditLog.create_for_service(service_name, action: 'test_dns', auditable: domain)
        expect(log.service_name).to eq(service_name)
        expect(log.action).to eq('test_dns')
        expect(log.auditable).to eq(domain)
        expect(log.status).to eq('started')
      end

      it 'creates log with default action' do
        log = ServiceAuditLog.create_for_service(service_name, auditable: domain)
        expect(log.action).to eq('process')
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create' do
      it 'sets default values' do
        audit_log = create(:service_audit_log)
        expect(audit_log.context).to eq({})
        expect(audit_log.changed_fields).to eq([])
      end
    end
  end
end 