require 'rails_helper'

RSpec.describe ServiceAuditLog, type: :model do
  describe 'associations' do
    it { should belong_to(:auditable) }
  end

  describe 'validations' do
    it { should validate_presence_of(:service_name) }
    it { should validate_presence_of(:action) }
    it { should validate_length_of(:service_name).is_at_most(100) }
    it { should validate_length_of(:action).is_at_most(50) }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(pending: 0, success: 1, failed: 2).with_prefix(true) }
  end

  describe 'scopes' do
    let!(:recent_log) { create(:service_audit_log, created_at: 1.hour.ago) }
    let!(:old_log) { create(:service_audit_log, created_at: 1.week.ago) }
    let!(:user_log) { create(:service_audit_log, service_name: 'user_enhancement_v1') }
    let!(:domain_log) { create(:service_audit_log, service_name: 'domain_testing_v1') }
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
      it 'filters by service name' do
        expect(ServiceAuditLog.for_service('user_enhancement_v1')).to contain_exactly(user_log)
      end
    end

    describe '.successful' do
      it 'returns only successful logs' do
        expect(ServiceAuditLog.successful).to contain_exactly(success_log)
      end
    end

    describe '.failed' do
      it 'returns only failed logs' do
        expect(ServiceAuditLog.failed).to contain_exactly(failed_log)
      end
    end

    describe '.for_auditable' do
      let(:user) { create(:user) }
      let!(:user_audit_log) { create(:service_audit_log, auditable: user) }

      it 'returns logs for specific auditable record' do
        expect(ServiceAuditLog.for_auditable(user)).to contain_exactly(user_audit_log)
      end
    end
  end

  describe 'instance methods' do
    let(:audit_log) { build(:service_audit_log) }

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
      it 'sets status to success and marks completed' do
        audit_log.started_at = 1.second.ago
        audit_log.mark_success!
        expect(audit_log).to be_status_success
        expect(audit_log.completed_at).to be_present
      end
    end

    describe '#mark_failed!' do
      it 'sets status to failed and marks completed' do
        audit_log.started_at = 1.second.ago
        audit_log.mark_failed!('Test error')
        expect(audit_log).to be_status_failed
        expect(audit_log.error_message).to eq('Test error')
        expect(audit_log.completed_at).to be_present
      end
    end

    describe '#add_context' do
      it 'merges context data' do
        audit_log.add_context(key1: 'value1')
        audit_log.add_context(key2: 'value2')
        expect(audit_log.context).to eq({ 'key1' => 'value1', 'key2' => 'value2' })
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
  end

  describe 'class methods' do
    describe '.batch_audit' do
      let(:users) { create_list(:user, 3) }

      it 'creates audit logs for batch processing' do
        expect do
          ServiceAuditLog.batch_audit(users, service_name: 'test_service_v1') do |user, audit_log|
            audit_log.mark_success!
          end
        end.to change(ServiceAuditLog, :count).by(3)
      end

      it 'yields each record with its audit log' do
        yielded_pairs = []
        ServiceAuditLog.batch_audit(users, service_name: 'test_service_v1') do |user, audit_log|
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
    end

    describe '.cleanup_old_logs' do
      let!(:old_logs) { create_list(:service_audit_log, 3, created_at: 100.days.ago) }
      let!(:recent_logs) { create_list(:service_audit_log, 2, created_at: 1.day.ago) }

      it 'removes logs older than specified days' do
        expect { ServiceAuditLog.cleanup_old_logs(90) }.to change(ServiceAuditLog, :count).by(-3)
        expect(ServiceAuditLog.all).to match_array(recent_logs)
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