require 'rails_helper'

RSpec.describe 'Service Audit System Integration', type: :integration do
  let!(:service_config) do
    create(:service_configuration,
           service_name: 'user_enhancement_v1',
           refresh_interval_hours: 24,
           batch_size: 100,
           retry_attempts: 2,
           active: true)
  end

  describe 'end-to-end service auditing workflow' do
    context 'with fresh users needing processing' do
      let!(:users) { create_list(:user, 5, email: 'test@gmail.com', name: 'Test User') }

      it 'processes users through the complete audit cycle' do
        # Verify users need the service
        users.each do |user|
          expect(user.needs_service?('user_enhancement_v1')).to be true
        end

        # Run the service
        expect {
          UserEnhancementService.new.call
        }.to change(ServiceAuditLog, :count).by(5)

        # Verify audit logs were created correctly
        audit_logs = ServiceAuditLog.where(service_name: 'user_enhancement_v1')
        expect(audit_logs.count).to eq(5)
        expect(audit_logs.all?(&:status_success?)).to be true

        # Verify users no longer need the service
        users.each do |user|
          expect(user.needs_service?('user_enhancement_v1')).to be false
        end

        # Verify audit log details
        audit_logs.each do |log|
          expect(log.service_name).to eq('user_enhancement_v1')
          expect(log.action).to eq('enhance')
          expect(log.started_at).to be_present
          expect(log.completed_at).to be_present
          expect(log.duration_ms).to be_present
          expect(log.context).to include('email_provider', 'name_length')
        end
      end

      it 'updates service performance statistics' do
        # Run the service
        UserEnhancementService.new.call

        # Check performance stats
        stat = ServicePerformanceStat.find_by(service_name: 'user_enhancement_v1')
        expect(stat).to be_present
        expect(stat.total_runs).to eq(5)
        expect(stat.successful_runs).to eq(5)
        expect(stat.failed_runs).to eq(0)
        expect(stat.success_rate_percent).to eq(100.0)
        expect(stat.avg_duration_ms).to be > 0
      end

      it 'creates latest service run records' do
        # Run the service
        UserEnhancementService.new.call

        # Check latest service runs
        latest_runs = LatestServiceRun.where(service_name: 'user_enhancement_v1')
        expect(latest_runs.count).to eq(5)

        users.each do |user|
          latest_run = latest_runs.find_by(auditable_type: 'User', auditable_id: user.id)
          expect(latest_run).to be_present
          expect(latest_run.status).to eq(1) # success
          expect(latest_run.completed_at).to be_present
        end
      end
    end

    context 'with error handling' do
      let!(:users) { create_list(:user, 3) }

      it 'handles partial failures gracefully' do
        # Mock one specific user to fail  
        allow(users.second).to receive(:update!).and_raise(StandardError, 'Processing failed')

        # Run the service and expect it to fail on the second user
        expect {
          User.with_service_audit('error_test_service') do |user, audit_log|
            user.update!(name: "Processed #{user.name}")
          end
        }.to raise_error(StandardError, 'Processing failed')

        # Verify mixed results in audit logs
        audit_logs = ServiceAuditLog.where(service_name: 'error_test_service')
        expect(audit_logs.where(status: :success).count).to eq(1) # First user succeeded
        expect(audit_logs.where(status: :failed).count).to eq(1)  # Second user failed
        expect(audit_logs.where(status: :pending).count).to eq(1) # Third user never processed

        failed_log = audit_logs.find_by(status: :failed)
        expect(failed_log.error_message).to eq('Processing failed')
      end
    end

    context 'with automatic model auditing' do
      it 'automatically creates audit logs for model changes' do
        # Create user - should trigger automatic audit
        user = nil
        expect {
          user = User.create!(name: 'Auto Audit Test', email: 'auto@test.com')
        }.to change(ServiceAuditLog, :count).by(1)

        create_log = ServiceAuditLog.where(auditable: user, action: 'create').first
        expect(create_log).to be_present
        expect(create_log.service_name).to eq('automatic_audit')

        # Update user - should trigger automatic audit
        expect {
          user.update!(name: 'Updated Name')
        }.to change(ServiceAuditLog, :count).by(1)

        update_log = ServiceAuditLog.where(auditable: user, action: 'update').first
        expect(update_log).to be_present
        expect(update_log.changed_fields).to include('name')
      end
    end

    context 'with service configuration management' do
      it 'respects inactive service configurations' do
        # Deactivate the service
        service_config.update!(active: false)

        # Create users
        users = create_list(:user, 2)

        # Users should not need inactive service
        users.each do |user|
          expect(user.needs_service?('user_enhancement_v1')).to be false
        end

        # Service should not process users
        expect {
          UserEnhancementService.new.call
        }.not_to change(ServiceAuditLog, :count)
      end

      it 'respects refresh interval settings' do
        # Create user and process once
        user = create(:user)
        UserEnhancementService.new.call

        # User should not need service again (within refresh interval)
        expect(user.needs_service?('user_enhancement_v1')).to be false

        # Change refresh interval to make user need service again
        service_config.update!(refresh_interval_hours: 1) # 1 hour ago, so user will need service

        # Now user should need service
        expect(user.needs_service?('user_enhancement_v1')).to be true
      end
    end

    context 'with database views' do
      let!(:user) { create(:user) }

      before do
        # Create some audit history
        create(:service_audit_log,
               auditable: user,
               service_name: 'user_enhancement_v1',
               status: :success,
               completed_at: 2.days.ago,
               duration_ms: 150)

        create(:service_audit_log,
               auditable: user,
               service_name: 'user_enhancement_v1',
               status: :success,
               completed_at: 1.day.ago,
               duration_ms: 200)
      end

      it 'provides accurate latest service run data' do
        latest_run = LatestServiceRun.find_by(
          auditable_type: 'User',
          auditable_id: user.id,
          service_name: 'user_enhancement_v1'
        )

        expect(latest_run).to be_present
        expect(latest_run.completed_at.to_date).to eq(1.day.ago.to_date)
        expect(latest_run.duration_ms).to eq(200)
      end

      it 'accurately tracks service performance' do
        stat = ServicePerformanceStat.find_by(service_name: 'user_enhancement_v1')
        expect(stat).to be_present
        expect(stat.total_runs).to eq(2)
        expect(stat.successful_runs).to eq(2)
        expect(stat.avg_duration_ms).to eq(175.0) # (150 + 200) / 2
      end

      it 'identifies records needing refresh correctly' do
        # Update service config to require refresh
        service_config.update!(refresh_interval_hours: 6) # 6 hours ago

        # Query the view directly
        needing_refresh = ActiveRecord::Base.connection.execute(
          "SELECT * FROM records_needing_refresh WHERE auditable_id = #{user.id} AND needs_refresh = true"
        )

        expect(needing_refresh.count).to eq(1)
      end
    end
  end

  describe 'rake task integration' do
    before do
      # Create some test data
      create_list(:user, 3)
      UserEnhancementService.new.call
    end

    it 'provides service statistics via rake task' do
      # This would typically be tested with system commands, but for integration
      # we'll test the underlying data that the rake task would display
      stats = ServicePerformanceStat.all
      expect(stats.count).to be > 0

      stat = stats.find_by(service_name: 'user_enhancement_v1')
      expect(stat.total_runs).to eq(3)
      expect(stat.success_rate_percent).to eq(100.0)
    end

    it 'supports audit log cleanup functionality' do
      # Create old logs
      old_logs = create_list :service_audit_log, 2, created_at: 100.days.ago

      # Test cleanup method
      expect {
        ServiceAuditLog.cleanup_old_logs(90)
      }.to change(ServiceAuditLog, :count).by(-2)
    end
  end
end 