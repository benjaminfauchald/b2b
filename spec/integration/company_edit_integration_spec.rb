require 'rails_helper'

RSpec.describe 'Company Edit Integration', type: :request do
  let(:user) { create(:user) }
  let(:company) do
    create(:company,
      website: 'https://old.com',
      email: 'old@example.com',
      phone: '+47 111 22 333',
      linkedin_url: nil
    )
  end

  before do
    sign_in user
  end

  describe 'PATCH /companies/:id' do
    context 'with valid parameters' do
      let(:valid_params) do
        {
          company: {
            website: 'https://new.com',
            email: 'new@example.com',
            phone: '+47 999 88 777',
            linkedin_url: 'https://linkedin.com/company/new'
          }
        }
      end

      it 'updates the company fields' do
        patch company_path(company), params: valid_params

        company.reload
        expect(company.website).to eq('https://new.com')
        expect(company.email).to eq('new@example.com')
        expect(company.phone).to eq('+47 999 88 777')
        expect(company.linkedin_url).to eq('https://linkedin.com/company/new')
      end

      it 'creates a ServiceAuditLog with service_name "user_update"' do
        expect {
          patch company_path(company), params: valid_params
        }.to change { ServiceAuditLog.where(service_name: 'user_update').count }.by(1)

        audit_log = ServiceAuditLog.where(service_name: 'user_update').last
        expect(audit_log.auditable).to eq(company)
        expect(audit_log.status).to eq('success')
        expect(audit_log.operation_type).to eq('update')
        expect(audit_log.table_name).to eq('companies')
        expect(audit_log.record_id).to eq(company.id.to_s)
        expect(audit_log.columns_affected).to contain_exactly('website', 'email', 'phone', 'linkedin_url')
        expect(audit_log.metadata['updated_by']).to eq(user.email)
      end

      it 'tracks old and new values in metadata' do
        patch company_path(company), params: valid_params

        audit_log = ServiceAuditLog.where(service_name: 'user_update').last
        changes = audit_log.metadata['changes']

        expect(changes['website']).to eq({
          'old_value' => 'https://old.com',
          'new_value' => 'https://new.com'
        })
        expect(changes['email']).to eq({
          'old_value' => 'old@example.com',
          'new_value' => 'new@example.com'
        })
      end
    end

    context 'when only updating some fields' do
      it 'only logs the changed fields' do
        patch company_path(company), params: {
          company: {
            website: 'https://updated.com',
            email: company.email  # Same value, should not be logged
          }
        }

        audit_log = ServiceAuditLog.where(service_name: 'user_update').last
        expect(audit_log.columns_affected).to eq([ 'website' ])
        expect(audit_log.metadata['fields_changed']).to eq([ 'website' ])
      end
    end

    context 'with AJAX request' do
      it 'returns JSON response and creates audit log' do
        patch company_path(company),
              params: { company: { website: 'https://ajax.com' } },
              headers: { 'X-Requested-With' => 'XMLHttpRequest' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to eq('Field updated successfully')

        audit_log = ServiceAuditLog.where(service_name: 'user_update').last
        expect(audit_log.columns_affected).to eq([ 'website' ])
        expect(audit_log.metadata['field']).to eq('website')
      end
    end

    context 'updating non-allowed fields' do
      it 'updates the field but does not create user_update audit log' do
        expect {
          patch company_path(company), params: { company: { company_name: 'New Name' } }
        }.not_to change { ServiceAuditLog.where(service_name: 'user_update').count }

        # Field is still updated (not restricted at model level)
        company.reload
        expect(company.company_name).to eq('New Name')
      end
    end

    context 'ServiceAuditLog compliance verification' do
      it 'creates fully compliant audit logs' do
        time_before = Time.current

        patch company_path(company), params: {
          company: { website: 'https://compliant.com' }
        }

        audit_log = ServiceAuditLog.where(service_name: 'user_update').last

        # Verify all required fields for SCT compliance
        expect(audit_log.auditable_type).to eq('Company')
        expect(audit_log.auditable_id).to eq(company.id)
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.status).to eq('success')
        expect(audit_log.table_name).to eq('companies')
        expect(audit_log.record_id).to eq(company.id.to_s)
        expect(audit_log.operation_type).to eq('update')
        expect(audit_log.columns_affected).to be_present
        expect(audit_log.execution_time_ms).to eq(0)
        expect(audit_log.started_at).to be >= time_before
        expect(audit_log.completed_at).to be >= audit_log.started_at
        expect(audit_log.metadata).to be_a(Hash)
        expect(audit_log.metadata).not_to be_empty

        # Verify metadata structure
        expect(audit_log.metadata['updated_by']).to eq(user.email)
        expect(audit_log.metadata['updated_at']).to be_present
        expect(Time.parse(audit_log.metadata['updated_at'])).to be_within(5.seconds).of(Time.current)
      end
    end
  end
end
