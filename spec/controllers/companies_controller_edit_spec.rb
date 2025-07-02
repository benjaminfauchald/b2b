require 'rails_helper'

RSpec.describe CompaniesController, type: :controller do
  let(:user) { create(:user) }
  let(:company) { create(:company) }

  before do
    sign_in user
  end

  describe 'PATCH #update' do
    context 'when updating company fields via form submission' do
      let(:new_attributes) do
        {
          website: 'https://newwebsite.com',
          email: 'newemail@example.com',
          phone: '+47 987 65 432',
          linkedin_url: 'https://linkedin.com/company/newcompany'
        }
      end

      it 'updates the company fields in the database' do
        patch :update, params: { id: company.id, company: new_attributes }

        company.reload
        expect(company.website).to eq('https://newwebsite.com')
        expect(company.email).to eq('newemail@example.com')
        expect(company.phone).to eq('+47 987 65 432')
        expect(company.linkedin_url).to eq('https://linkedin.com/company/newcompany')
      end

      it 'creates a ServiceAuditLog entry with service_name "user_update"' do
        expect {
          patch :update, params: { id: company.id, company: new_attributes }
        }.to change { ServiceAuditLog.count }.by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.auditable).to eq(company)
      end

      it 'logs all changed fields in columns_affected' do
        # Set initial values
        company.update!(
          website: 'https://oldwebsite.com',
          email: 'oldemail@example.com',
          phone: '+47 123 45 678',
          linkedin_url: nil
        )

        patch :update, params: { id: company.id, company: new_attributes }

        audit_log = ServiceAuditLog.last
        expect(audit_log.columns_affected).to contain_exactly('website', 'email', 'phone', 'linkedin_url')
      end

      it 'stores old and new values in metadata' do
        company.update!(
          website: 'https://oldwebsite.com',
          email: 'oldemail@example.com'
        )

        patch :update, params: { id: company.id, company: { website: 'https://newwebsite.com', email: 'newemail@example.com' } }

        audit_log = ServiceAuditLog.last
        metadata = audit_log.metadata

        expect(metadata['changes']['website']).to eq({
          'old_value' => 'https://oldwebsite.com',
          'new_value' => 'https://newwebsite.com'
        })
        expect(metadata['changes']['email']).to eq({
          'old_value' => 'oldemail@example.com',
          'new_value' => 'newemail@example.com'
        })
        expect(metadata['updated_by']).to eq(user.email)
      end

      it 'sets all required ServiceAuditLog fields for compliance' do
        patch :update, params: { id: company.id, company: { website: 'https://test.com' } }

        audit_log = ServiceAuditLog.last

        # Check all required fields for ServiceAuditLog compliance
        expect(audit_log.auditable_type).to eq('Company')
        expect(audit_log.auditable_id).to eq(company.id)
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.status).to eq('success')
        expect(audit_log.table_name).to eq('companies')
        expect(audit_log.record_id).to eq(company.id.to_s)
        expect(audit_log.operation_type).to eq('update')
        expect(audit_log.started_at).to be_present
        expect(audit_log.completed_at).to be_present
        expect(audit_log.execution_time_ms).to eq(0)
        expect(audit_log.metadata).to be_a(Hash)
        expect(audit_log.metadata['updated_at']).to be_present
      end

      it 'does not create audit log if no allowed fields are changed' do
        # Update only non-allowed fields
        expect {
          patch :update, params: { id: company.id, company: { company_name: 'New Name' } }
        }.not_to change { ServiceAuditLog.where(service_name: 'user_update').count }
      end

      it 'only logs changes to allowed fields' do
        patch :update, params: {
          id: company.id,
          company: {
            website: 'https://test.com',
            company_name: 'New Name',  # This should not be logged
            registration_number: '999999999'  # This should not be logged
          }
        }

        audit_log = ServiceAuditLog.last
        expect(audit_log.columns_affected).to eq([ 'website' ])
        expect(audit_log.metadata['fields_changed']).to eq([ 'website' ])
      end

      it 'redirects to company show page after successful update' do
        patch :update, params: { id: company.id, company: { website: 'https://test.com' } }
        expect(response).to redirect_to(company_path(company))
      end

      it 'shows success notice after update' do
        patch :update, params: { id: company.id, company: { website: 'https://test.com' } }
        expect(flash[:notice]).to eq('Company was successfully updated.')
      end
    end

    context 'when updating via AJAX (inline edit)' do
      it 'updates single field and creates audit log' do
        expect {
          patch :update, params: { id: company.id, company: { website: 'https://ajax-test.com' } },
                xhr: true
        }.to change { ServiceAuditLog.count }.by(1)

        company.reload
        expect(company.website).to eq('https://ajax-test.com')

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.columns_affected).to eq([ 'website' ])
        expect(audit_log.metadata['field']).to eq('website')
      end

      it 'returns JSON success response' do
        patch :update, params: { id: company.id, company: { email: 'ajax@example.com' } },
              xhr: true

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to eq('Field updated successfully')
      end

      it 'returns error for non-allowed fields' do
        patch :update, params: { id: company.id, company: { company_name: 'Hacked Name' } },
              xhr: true

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Field not allowed for inline editing')
      end
    end

    context 'with validation errors' do
      it 'does not create audit log on validation failure' do
        # Stub the company to fail validation
        allow_any_instance_of(Company).to receive(:update).and_return(false)
        allow_any_instance_of(Company).to receive(:errors).and_return(
          ActiveModel::Errors.new(Company.new).tap { |e| e.add(:base, "Validation failed") }
        )

        # In controller specs, template rendering doesn't happen by default
        # We need to check if the render method is called with correct params
        expect(controller).to receive(:render).with(:edit, status: :unprocessable_entity)

        expect {
          patch :update, params: { id: company.id, company: { email: 'test@example.com' } }
        }.not_to change { ServiceAuditLog.count }
      end

      it 'returns error for AJAX requests on validation failure' do
        # Create a real errors object and add an error to it
        allow_any_instance_of(Company).to receive(:update) do |company_instance|
          company_instance.errors.add(:email, 'is invalid')
          false
        end

        patch :update, params: { id: company.id, company: { email: 'invalid' } }, xhr: true

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Email is invalid')
      end
    end
  end
end
