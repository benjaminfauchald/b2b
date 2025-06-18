require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it "is valid with valid attributes" do
      user = User.new(name: "Example", email: "user_#{SecureRandom.hex(4)}@example.com", password: 'Password123!')
      expect(user).to be_valid
    end
  end

  describe 'ServiceAuditable concern' do
    it 'includes ServiceAuditable module' do
      expect(User.included_modules).to include(ServiceAuditable)
    end

    it 'has many service_audit_logs' do
      association = User.reflect_on_association(:service_audit_logs)
      expect(association.macro).to eq :has_many
      expect(association.options[:as]).to eq :auditable
      expect(association.options[:dependent]).to eq :destroy
    end

    describe 'automatic auditing' do
      it 'creates audit log on creation' do
        expect {
          User.create!(name: "Test User", email: "test_#{SecureRandom.hex(4)}@example.com", password: 'Password123!')
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('automatic_audit')
        expect(audit_log.action).to eq('create')
        expect(audit_log.auditable_type).to eq('User')
      end

      it 'creates audit log on update' do
        user = create(:user)

        expect {
          user.update!(name: "New Name")
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('automatic_audit')
        expect(audit_log.action).to eq('update')
        expect(audit_log.changed_fields).to include('name')
      end
    end

    describe '.with_service_audit' do
      let!(:users) { create_list(:user, 3) }

      it 'processes users with audit logging' do
        # Clear existing automatic audit logs from user creation
        ServiceAuditLog.where(service_name: 'automatic_audit').delete_all

        expect {
          User.with_service_audit('test_service', action: 'bulk_process') do |user, audit_log|
            user.update!(name: "Processed #{user.name}")
          end
        }.to change(ServiceAuditLog, :count).by(6) # 3 for service + 3 for automatic auditing

        service_audit_logs = ServiceAuditLog.where(service_name: 'test_service')
        expect(service_audit_logs.count).to eq(3)
        expect(service_audit_logs.all?(&:status_success?)).to be true

        automatic_audit_logs = ServiceAuditLog.where(service_name: 'automatic_audit')
        expect(automatic_audit_logs.count).to eq(3) # One for each user update
      end

      it 'handles errors during processing' do
        allow_any_instance_of(User).to receive(:update!).and_raise(StandardError, "Test error")

        expect {
          User.with_service_audit('error_service') do |user, audit_log|
            user.update!(name: "Should fail")
          end
        }.to raise_error(StandardError, "Test error")

        audit_logs = ServiceAuditLog.where(service_name: 'error_service')
        expect(audit_logs.all?(&:status_failed?)).to be true
        expect(audit_logs.first.error_message).to eq("Test error")
      end
    end

    describe '.needing_service' do
      let!(:user) { create(:user) }
      let!(:config) { create(:service_configuration, service_name: 'test_service', refresh_interval_hours: 24) }

      context 'when user has never been processed' do
        it 'returns the user' do
          users = User.needing_service('test_service')
          expect(users).to include(user)
        end
      end

      context 'when user was processed recently' do
        before do
          create(:service_audit_log,
                 auditable: user,
                 service_name: 'test_service',
                 status: :success,
                 completed_at: 1.hour.ago)
        end

        it 'does not return the user' do
          users = User.needing_service('test_service')
          expect(users).not_to include(user)
        end
      end

      context 'when user was processed long ago' do
        before do
          create(:service_audit_log,
                 auditable: user,
                 service_name: 'test_service',
                 status: :success,
                 completed_at: 2.days.ago)
        end

        it 'returns the user' do
          users = User.needing_service('test_service')
          expect(users).to include(user)
        end
      end
    end

    describe '#needs_service?' do
      let!(:user) { create(:user) }
      let!(:config) { create(:service_configuration, service_name: 'test_service', refresh_interval_hours: 24) }

      it 'returns true when service has never been run' do
        expect(user.needs_service?('test_service')).to be true
      end

      it 'returns false when service was run recently' do
        create(:service_audit_log,
               auditable: user,
               service_name: 'test_service',
               status: :success,
               completed_at: 1.hour.ago)

        expect(user.needs_service?('test_service')).to be false
      end

      it 'returns true when service was run long ago' do
        create(:service_audit_log,
               auditable: user,
               service_name: 'test_service',
               status: :success,
               completed_at: 2.days.ago)

        expect(user.needs_service?('test_service')).to be true
      end

      it 'returns false when service configuration is inactive' do
        config.update!(active: false)
        expect(user.needs_service?('test_service')).to be false
      end
    end
  end
end
