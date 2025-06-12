require 'rails_helper'

RSpec.describe ServiceAuditable, type: :concern do
  # Create a test model that includes the concern
  let(:test_class) do
    Class.new(ApplicationRecord) do
      self.table_name = 'users'
      include ServiceAuditable
    end
  end

  let(:test_instance) { test_class.new(name: 'Test User', email: 'test@example.com') }

  describe 'associations' do
    it 'has many service_audit_logs' do
      expect(test_class.reflect_on_association(:service_audit_logs)).to be_present
      expect(test_class.reflect_on_association(:service_audit_logs).macro).to eq(:has_many)
      expect(test_class.reflect_on_association(:service_audit_logs).options[:as]).to eq(:auditable)
      expect(test_class.reflect_on_association(:service_audit_logs).options[:dependent]).to eq(:destroy)
    end
  end

  describe 'callbacks' do
    context 'when audit is enabled' do
      before do
        allow(test_instance).to receive(:audit_enabled?).and_return(true)
      end

      it 'audits creation' do
        expect(test_instance).to receive(:audit_creation)
        test_instance.run_callbacks(:create)
      end

      it 'audits updates' do
        expect(test_instance).to receive(:audit_update)
        test_instance.run_callbacks(:update)
      end
    end

    context 'when audit is disabled' do
      before do
        allow(test_instance).to receive(:audit_enabled?).and_return(false)
      end

      it 'does not audit creation' do
        expect(test_instance).not_to receive(:audit_creation)
        test_instance.run_callbacks(:create)
      end

      it 'does not audit updates' do
        expect(test_instance).not_to receive(:audit_update)
        test_instance.run_callbacks(:update)
      end
    end
  end

  describe 'instance methods' do
    let(:user) { create(:user) }
    let(:auditable_user) do
      user.extend(ServiceAuditable)
    end

    describe '#audit_service_operation' do
      it 'creates audit log and yields with it' do
        expect do
          auditable_user.audit_service_operation('test_service_v1', action: 'custom') do |audit_log|
            expect(audit_log).to be_a(ServiceAuditLog)
            expect(audit_log.service_name).to eq('test_service_v1')
            expect(audit_log.action).to eq('custom')
            expect(audit_log.auditable).to eq(auditable_user)
            audit_log.mark_success!
          end
        end.to change(ServiceAuditLog, :count).by(1)
      end

      it 'handles exceptions and marks as failed' do
        expect do
          auditable_user.audit_service_operation('test_service_v1') do |audit_log|
            raise StandardError, 'Test error'
          end
        end.to raise_error(StandardError, 'Test error')

        audit_log = ServiceAuditLog.last
        expect(audit_log.status_failed?).to be true
        expect(audit_log.error_message).to eq('Test error')
      end

      it 'returns context data from block' do
        result = auditable_user.audit_service_operation('test_service_v1') do |audit_log|
          audit_log.mark_success!
          { processed: true, count: 5 }
        end

        expect(result).to eq({ processed: true, count: 5 })
      end
    end

    describe '#needs_service?' do
      let!(:config) { create(:service_configuration, service_name: 'test_service_v1', refresh_interval_hours: 24) }

      context 'when no previous run exists' do
        it 'returns true' do
          expect(auditable_user.needs_service?('test_service_v1')).to be true
        end
      end

      context 'when previous run is within refresh interval' do
        before do
          create(:service_audit_log, :success, 
                 auditable: auditable_user, 
                 service_name: 'test_service_v1',
                 completed_at: 12.hours.ago)
        end

        it 'returns false' do
          expect(auditable_user.needs_service?('test_service_v1')).to be false
        end
      end

      context 'when previous run is outside refresh interval' do
        before do
          create(:service_audit_log, :success,
                 auditable: auditable_user,
                 service_name: 'test_service_v1', 
                 completed_at: 25.hours.ago)
        end

        it 'returns true' do
          expect(auditable_user.needs_service?('test_service_v1')).to be true
        end
      end

      context 'when service configuration does not exist' do
        it 'returns true' do
          expect(auditable_user.needs_service?('nonexistent_service')).to be true
        end
      end
    end

    describe '#last_service_run' do
      let!(:old_run) { create(:service_audit_log, :success, auditable: auditable_user, service_name: 'test_service_v1', completed_at: 2.days.ago) }
      let!(:recent_run) { create(:service_audit_log, :success, auditable: auditable_user, service_name: 'test_service_v1', completed_at: 1.day.ago) }

      it 'returns the most recent successful run for the service' do
        expect(auditable_user.last_service_run('test_service_v1')).to eq(recent_run)
      end

      it 'returns nil if no successful runs exist' do
        expect(auditable_user.last_service_run('nonexistent_service')).to be_nil
      end
    end

    describe '#audit_enabled?' do
      it 'returns true by default' do
        expect(auditable_user.audit_enabled?).to be true
      end

      context 'when Rails configuration disables auditing' do
        before do
          allow(Rails.application.config).to receive(:respond_to?).with(:service_auditing_enabled).and_return(true)
          allow(Rails.application.config).to receive(:service_auditing_enabled).and_return(false)
        end

        it 'returns false' do
          expect(auditable_user.audit_enabled?).to be false
        end
      end
    end
  end

  describe 'class methods' do
    describe '.with_service_audit' do
      let(:users) { create_list(:user, 3) }
      let(:auditable_class) do
        Class.new(User) do
          include ServiceAuditable
        end
      end

      it 'creates audit logs for batch processing' do
        expect do
          auditable_class.with_service_audit('batch_test_v1', action: 'batch_process') do |user, audit_log|
            audit_log.mark_success!
          end
        end.to change(ServiceAuditLog, :count).by(auditable_class.count)
      end

      it 'yields each record with its audit log' do
        yielded_pairs = []
        auditable_class.with_service_audit('batch_test_v1') do |user, audit_log|
          yielded_pairs << [user, audit_log]
          audit_log.mark_success!
        end

        expect(yielded_pairs.size).to eq(auditable_class.count)
        yielded_pairs.each do |user, audit_log|
          expect(user).to be_a(auditable_class)
          expect(audit_log).to be_a(ServiceAuditLog)
          expect(audit_log.auditable).to eq(user)
        end
      end
    end

    describe '.needing_service' do
      let!(:config) { create(:service_configuration, service_name: 'test_service_v1', refresh_interval_hours: 24) }
      let!(:user1) { create(:user) }
      let!(:user2) { create(:user) }
      let!(:user3) { create(:user) }

      before do
        # user1 has no runs - needs service
        # user2 has recent run - doesn't need service
        create(:service_audit_log, :success, auditable: user2, service_name: 'test_service_v1', completed_at: 12.hours.ago)
        # user3 has old run - needs service
        create(:service_audit_log, :success, auditable: user3, service_name: 'test_service_v1', completed_at: 25.hours.ago)
      end

      it 'returns records that need the service' do
        needing_users = User.needing_service('test_service_v1')
        expect(needing_users).to include(user1, user3)
        expect(needing_users).not_to include(user2)
      end
    end
  end

  describe 'private methods' do
    let(:user) { create(:user) }
    let(:auditable_user) do
      user.extend(ServiceAuditable)
    end

    describe '#audit_creation' do
      it 'creates audit log for creation' do
        expect do
          auditable_user.send(:audit_creation)
        end.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('model_lifecycle')
        expect(audit_log.action).to eq('create')
        expect(audit_log.auditable).to eq(auditable_user)
      end
    end

    describe '#audit_update' do
      before do
        auditable_user.name = 'Updated Name'
      end

      it 'creates audit log for update with changed fields' do
        expect do
          auditable_user.send(:audit_update)
        end.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('model_lifecycle')
        expect(audit_log.action).to eq('update')
        expect(audit_log.changed_fields).to include('name')
      end
    end
  end
end 