require 'rails_helper'

RSpec.describe PeopleController, type: :controller do
  let(:user) { create(:user) }
  let(:person) { create(:person) }

  before do
    sign_in user
  end

  describe 'PATCH #update' do
    context 'when updating person fields via form submission' do
      let(:new_attributes) do
        {
          email: 'newemail@example.com',
          phone: '+47 987 65 432'
        }
      end

      it 'updates the person fields in the database' do
        patch :update, params: { id: person.id, person: new_attributes }

        person.reload
        expect(person.email).to eq('newemail@example.com')
        expect(person.phone).to eq('+47 987 65 432')
      end

      it 'creates a ServiceAuditLog entry with service_name "user_update"' do
        expect {
          patch :update, params: { id: person.id, person: new_attributes }
        }.to change { ServiceAuditLog.count }.by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.auditable).to eq(person)
      end

      it 'logs all changed fields in columns_affected' do
        # Set initial values
        person.update!(
          email: 'oldemail@example.com',
          phone: '+47 123 45 678'
        )

        patch :update, params: { id: person.id, person: new_attributes }

        audit_log = ServiceAuditLog.last
        expect(audit_log.columns_affected).to contain_exactly('email', 'phone')
      end

      it 'stores old and new values in metadata' do
        person.update!(
          email: 'oldemail@example.com',
          phone: '+47 123 45 678'
        )

        patch :update, params: { id: person.id, person: new_attributes }

        audit_log = ServiceAuditLog.last
        metadata = audit_log.metadata

        expect(metadata['changes']['email']).to eq({
          'old_value' => 'oldemail@example.com',
          'new_value' => 'newemail@example.com'
        })
        expect(metadata['changes']['phone']).to eq({
          'old_value' => '+47 123 45 678',
          'new_value' => '+47 987 65 432'
        })
        expect(metadata['updated_by']).to eq(user.email)
      end

      it 'sets all required ServiceAuditLog fields for compliance' do
        patch :update, params: { id: person.id, person: { email: 'test@example.com' } }

        audit_log = ServiceAuditLog.last

        # Check all required fields for ServiceAuditLog compliance
        expect(audit_log.auditable_type).to eq('Person')
        expect(audit_log.auditable_id).to eq(person.id)
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.status).to eq('success')
        expect(audit_log.table_name).to eq('people')
        expect(audit_log.record_id).to eq(person.id.to_s)
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
          patch :update, params: { id: person.id, person: { name: 'New Name' } }
        }.not_to change { ServiceAuditLog.where(service_name: 'user_update').count }
      end

      it 'only logs changes to allowed fields' do
        patch :update, params: {
          id: person.id,
          person: {
            email: 'test@example.com',
            name: 'New Name',  # This should not be logged
            title: 'New Title'  # This should not be logged
          }
        }

        audit_log = ServiceAuditLog.last
        expect(audit_log.columns_affected).to eq([ 'email' ])
        expect(audit_log.metadata['fields_changed']).to eq([ 'email' ])
      end

      it 'redirects to person show page after successful update' do
        patch :update, params: { id: person.id, person: { email: 'test@example.com' } }
        expect(response).to redirect_to(person_path(person))
      end

      it 'shows success notice after update' do
        patch :update, params: { id: person.id, person: { email: 'test@example.com' } }
        expect(flash[:notice]).to eq('Person was successfully updated.')
      end
    end

    context 'when updating via AJAX (inline edit)' do
      it 'updates single field and creates audit log' do
        expect {
          patch :update, params: { id: person.id, person: { email: 'ajax@example.com' } },
                xhr: true
        }.to change { ServiceAuditLog.count }.by(1)

        person.reload
        expect(person.email).to eq('ajax@example.com')

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('user_update')
        expect(audit_log.columns_affected).to eq([ 'email' ])
        expect(audit_log.metadata['field']).to eq('email')
      end

      it 'returns JSON success response' do
        patch :update, params: { id: person.id, person: { phone: '+47 999 88 777' } },
              xhr: true

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to eq('Field updated successfully')
      end

      it 'returns error for non-allowed fields' do
        patch :update, params: { id: person.id, person: { name: 'Hacked Name' } },
              xhr: true

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Field not allowed for inline editing')
      end
    end

    context 'with validation errors' do
      it 'does not create audit log on validation failure' do
        # Stub the person to fail validation
        allow_any_instance_of(Person).to receive(:update).and_return(false)
        allow_any_instance_of(Person).to receive(:errors).and_return(
          ActiveModel::Errors.new(Person.new).tap { |e| e.add(:base, "Validation failed") }
        )

        expect {
          patch :update, params: { id: person.id, person: { email: 'test@example.com' } }
        }.not_to change { ServiceAuditLog.count }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error for AJAX requests on validation failure' do
        # Create a real errors object and add an error to it
        allow_any_instance_of(Person).to receive(:update) do |person_instance|
          person_instance.errors.add(:email, 'is invalid')
          false
        end

        patch :update, params: { id: person.id, person: { email: 'invalid' } }, xhr: true

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Email is invalid')
      end
    end
  end
end
