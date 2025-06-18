require 'rails_helper'

RSpec.describe 'Service Audit System Integration', type: :integration do
  let(:service_name) { 'test_service' }
  let(:auditable) { create(:company) }

  before do
    # Ensure service is configured
    create(:service_configuration, 
      service_name: service_name,
      refresh_interval_hours: 24,
      active: true
    )
  end

  describe 'service audit flow' do
    it 'creates and updates audit logs for successful operations' do
      audit_log = ServiceAuditLog.create!(
        service_name: service_name,
        auditable: auditable,
        operation_type: 'process',
        started_at: Time.current,
        metadata: { 'status' => 'initialized' },
        table_name: 'companies',
        record_id: auditable.id,
        columns_affected: ['unspecified']
      )
      audit_log.mark_success!({ 'result' => 'ok' })
      expect(audit_log.reload).to have_attributes(
        status: 'success',
        completed_at: be_present,
        execution_time_ms: be_positive
      )
    end

    it 'creates and updates audit logs for failed operations' do
      audit_log = ServiceAuditLog.create!(
        service_name: service_name,
        auditable: auditable,
        operation_type: 'process',
        started_at: Time.current,
        metadata: { 'status' => 'initialized' },
        table_name: 'companies',
        record_id: auditable.id,
        columns_affected: ['unspecified']
      )
      error_message = 'Test error'
      audit_log.mark_failed!(error_message, { 'error' => error_message })
      expect(audit_log.reload).to have_attributes(
        status: 'failed',
        error_message: error_message,
        completed_at: be_present,
        execution_time_ms: be_positive
      )
    end

    it 'respects service configuration' do
      # Deactivate the service
      ServiceConfiguration.find_by(service_name: service_name).update!(active: false)

      # Verify service is inactive
      expect(ServiceConfiguration.active?(service_name)).to be false

      # Reactivate the service
      ServiceConfiguration.find_by(service_name: service_name).update!(active: true)

      # Verify service is active
      expect(ServiceConfiguration.active?(service_name)).to be true
    end
  end
end 