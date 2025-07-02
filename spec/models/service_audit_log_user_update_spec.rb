require 'rails_helper'

RSpec.describe ServiceAuditLog, type: :model do
  describe 'user_update service compliance' do
    let(:company) { create(:company) }
    let(:user) { create(:user) }

    context 'when creating a user_update audit log' do
      let(:audit_log_attributes) do
        {
          auditable: company,
          service_name: 'user_update',
          status: :success,
          started_at: Time.current,
          completed_at: Time.current,
          table_name: 'companies',
          record_id: company.id.to_s,
          operation_type: 'update',
          columns_affected: [ 'website', 'email' ],
          execution_time_ms: 0,
          metadata: {
            fields_changed: [ 'website', 'email' ],
            changes: {
              'website' => { 'old_value' => nil, 'new_value' => 'https://example.com' },
              'email' => { 'old_value' => 'old@example.com', 'new_value' => 'new@example.com' }
            },
            updated_by: user.email,
            updated_at: Time.current.iso8601
          }
        }
      end

      it 'creates a valid audit log entry' do
        audit_log = ServiceAuditLog.new(audit_log_attributes)
        expect(audit_log).to be_valid
      end

      it 'saves successfully with all required fields' do
        audit_log = ServiceAuditLog.create!(audit_log_attributes)

        expect(audit_log.persisted?).to be true
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.auditable).to eq(company)
      end

      it 'enforces required fields' do
        # Test missing auditable
        invalid_log = ServiceAuditLog.new(audit_log_attributes.except(:auditable))
        expect(invalid_log).not_to be_valid
        expect(invalid_log.errors[:auditable]).to be_present

        # Test missing service_name
        invalid_log = ServiceAuditLog.new(audit_log_attributes.except(:service_name))
        expect(invalid_log).not_to be_valid
        expect(invalid_log.errors[:service_name]).to be_present

        # Test missing metadata
        invalid_log = ServiceAuditLog.new(audit_log_attributes.except(:metadata))
        expect(invalid_log).not_to be_valid
        expect(invalid_log.errors[:metadata]).to be_present
      end

      it 'accepts valid status values' do
        # Test pending and success statuses
        %w[pending success].each do |status|
          audit_log = ServiceAuditLog.new(audit_log_attributes.merge(status: status))
          expect(audit_log).to be_valid
        end

        # Test failed status requires error in metadata
        failed_attributes = audit_log_attributes.merge(
          status: 'failed',
          metadata: audit_log_attributes[:metadata].merge('error' => 'Test error message')
        )
        audit_log = ServiceAuditLog.new(failed_attributes)
        expect(audit_log).to be_valid
      end

      it 'stores metadata as JSON' do
        audit_log = ServiceAuditLog.create!(audit_log_attributes)

        expect(audit_log.metadata).to be_a(Hash)
        expect(audit_log.metadata['updated_by']).to eq(user.email)
        expect(audit_log.metadata['changes']['website']['new_value']).to eq('https://example.com')
      end

      it 'tracks columns_affected as an array' do
        audit_log = ServiceAuditLog.create!(audit_log_attributes)

        expect(audit_log.columns_affected).to be_an(Array)
        expect(audit_log.columns_affected).to eq([ 'website', 'email' ])
      end
    end

    context 'querying user_update logs' do
      before do
        # Create various audit logs
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'user_update',
          status: :success,
          started_at: 1.hour.ago,
          completed_at: 1.hour.ago,
          table_name: 'companies',
          record_id: company.id.to_s,
          operation_type: 'update',
          columns_affected: [ 'website' ],
          execution_time_ms: 0,
          metadata: { field: 'website', updated_by: user.email }
        )

        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'company_financial_data',
          status: :success,
          started_at: 2.hours.ago,
          completed_at: 2.hours.ago,
          table_name: 'companies',
          record_id: company.id.to_s,
          operation_type: 'sync',
          columns_affected: [ 'revenue' ],
          execution_time_ms: 1500,
          metadata: { 'service' => 'company_financial_data' }
        )
      end

      it 'filters by service_name correctly' do
        user_updates = ServiceAuditLog.where(service_name: 'user_update')
        expect(user_updates.count).to eq(1)
        expect(user_updates.first.service_name).to eq('user_update')
      end

      it 'filters by auditable correctly' do
        company_logs = ServiceAuditLog.where(auditable: company)
        expect(company_logs.count).to eq(2)
        expect(company_logs.pluck(:service_name)).to contain_exactly('user_update', 'company_financial_data')
      end

      it 'can query by operation_type' do
        # Only count logs created in this context
        update_logs = ServiceAuditLog.where(operation_type: 'update', auditable: company)
        expect(update_logs.count).to eq(1)
        expect(update_logs.first.service_name).to eq('user_update')
      end
    end

    context 'tracking different field types' do
      it 'handles nil to value changes' do
        audit_log = ServiceAuditLog.create!(
          auditable: company,
          service_name: 'user_update',
          status: :success,
          started_at: Time.current,
          completed_at: Time.current,
          table_name: 'companies',
          record_id: company.id.to_s,
          operation_type: 'update',
          columns_affected: [ 'website' ],
          execution_time_ms: 0,
          metadata: {
            field: 'website',
            old_value: nil,
            new_value: 'https://example.com',
            updated_by: user.email,
            updated_at: Time.current.iso8601
          }
        )

        expect(audit_log.metadata['old_value']).to be_nil
        expect(audit_log.metadata['new_value']).to eq('https://example.com')
      end

      it 'handles value to nil changes' do
        audit_log = ServiceAuditLog.create!(
          auditable: company,
          service_name: 'user_update',
          status: :success,
          started_at: Time.current,
          completed_at: Time.current,
          table_name: 'companies',
          record_id: company.id.to_s,
          operation_type: 'update',
          columns_affected: [ 'phone' ],
          execution_time_ms: 0,
          metadata: {
            field: 'phone',
            old_value: '+47 123 45 678',
            new_value: nil,
            updated_by: user.email,
            updated_at: Time.current.iso8601
          }
        )

        expect(audit_log.metadata['old_value']).to eq('+47 123 45 678')
        expect(audit_log.metadata['new_value']).to be_nil
      end
    end
  end
end
