require 'rails_helper'

RSpec.describe ServiceAuditLog, type: :model do
  # Test constants for clarity
  let(:service_name) { 'test_service' }
  let(:auditable) { create(:company) } # Using company as a simple auditable object
  let(:action) { 'process' }
  let(:context) { { 'test_key' => 'test_value' } }

  describe 'validations' do
    it 'requires a service name' do
      log = build(:service_audit_log, service_name: nil, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: '1', operation_type: 'process', columns_affected: [ 'unspecified' ])
      expect(log).not_to be_valid
      expect(log.errors[:service_name]).to include("can't be blank")
    end

    it 'requires an auditable object' do
      log = build(:service_audit_log, auditable: nil, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: '1', operation_type: 'process', columns_affected: [ 'unspecified' ])
      expect(log).not_to be_valid
      expect(log.errors[:auditable]).to include("can't be blank")
    end
  end

  describe 'status management' do
    it 'starts with pending status' do
      log = create(:service_audit_log, service_name: service_name, auditable: auditable, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: auditable.id, operation_type: 'process', columns_affected: [ 'unspecified' ])
      expect(log.status).to eq('pending')
    end

    it 'can be marked as successful' do
      log = create(:service_audit_log, service_name: service_name, auditable: auditable, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: auditable.id, operation_type: 'process', columns_affected: [ 'unspecified' ])
      log.mark_success!({ 'result' => 'ok' })

      expect(log.status).to eq('success')
      expect(log.completed_at).not_to be_nil
      expect(log.execution_time_ms).not_to be_nil
      expect(log.metadata).to include('result' => 'ok')
    end

    it 'can be marked as failed with error message' do
      log = create(:service_audit_log, service_name: service_name, auditable: auditable, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: auditable.id, operation_type: 'process', columns_affected: [ 'unspecified' ])
      error_message = 'Test error'
      log.mark_failed!(error_message)

      expect(log.status).to eq('failed')
      expect(log.error_message).to eq('Test error')
      expect(log.completed_at).not_to be_nil
      expect(log.execution_time_ms).not_to be_nil
    end
  end

  describe 'duration calculation' do
    it 'calculates duration when completed' do
      log = create(:service_audit_log,
        service_name: service_name,
        auditable: auditable,
        started_at: 1.minute.ago,
        metadata: { 'status' => 'initialized' },
        table_name: 'companies',
        record_id: auditable.id,
        operation_type: 'process',
        columns_affected: [ 'unspecified' ]
      )
      log.update!(completed_at: Time.current)
      log.update_column(:execution_time_ms, log.calculate_duration)
      expect(log.execution_time_ms).to be_within(100).of(60_000)
    end

    it 'returns nil duration for pending logs' do
      log = create(:service_audit_log,
        service_name: service_name,
        auditable: auditable,
        metadata: { 'status' => 'initialized' },
        table_name: 'companies',
        record_id: auditable.id,
        operation_type: 'process',
        columns_affected: [ 'unspecified' ]
      )

      expect(log.execution_time_ms).to be_nil
    end
  end

  describe 'scopes' do
    before do
      # Create logs with different statuses
      create(:service_audit_log, service_name: service_name, status: :success, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: '1', operation_type: 'process', columns_affected: [ 'unspecified' ])
      create(:service_audit_log, service_name: service_name, status: :failed, metadata: { 'status' => 'initialized', 'error' => 'test error' }, table_name: 'companies', record_id: '1', operation_type: 'process', columns_affected: [ 'unspecified' ])
      create(:service_audit_log, service_name: service_name, status: :pending, metadata: { 'status' => 'initialized' }, table_name: 'companies', record_id: '1', operation_type: 'process', columns_affected: [ 'unspecified' ])
    end

    it 'finds successful logs' do
      expect(ServiceAuditLog.successful.count).to be >= 1
    end

    it 'finds failed logs' do
      expect(ServiceAuditLog.failed.count).to be >= 1
    end

    it 'finds pending logs' do
      expect(ServiceAuditLog.pending.count).to be >= 1
    end
  end
end
