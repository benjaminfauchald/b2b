require 'rails_helper'

# Minimal, SCT-compliant test for CompanyFinancialsService
# This test demonstrates how to use the service and how it logs to the ServiceAuditLog (SCT)
RSpec.describe CompanyFinancialsService, type: :service do
  let(:company) { create(:company, registration_number: '123456789') }
  let(:service) { described_class.new(company) }

  it 'creates an SCT audit log entry when called' do
    # Call the service (simulate a successful run)
    allow(service).to receive(:fetch_and_update_financials).and_return({ changed_fields: ['revenue'], success: true })
    result = service.call

    # Check that an audit log was created with correct SCT fields
    audit_log = ServiceAuditLog.last
    expect(audit_log).to have_attributes(
      service_name: 'company_financials',
      table_name: 'companies',
      record_id: company.id.to_s,
      operation_type: 'update',
      status: 'success',
      columns_affected: ['revenue'], # changed_fields are passed in mark_success!
      metadata: include('company_id' => company.id, 'registration_number' => company.registration_number)
    )
    expect(result[:success]).to be true
  end

  it 'logs a failed SCT audit entry on error' do
    # Simulate an error in the service
    allow(service).to receive(:fetch_and_update_financials).and_raise(StandardError, 'API failure')
    expect {
      service.call rescue nil
    }.to change { ServiceAuditLog.where(status: 'failed').count }.by(1)
    log = ServiceAuditLog.order(:created_at).last
    expect(log.status).to eq('failed')
    expect(log.error_message).to eq('API failure')
    expect(log.table_name).to eq('companies')
    expect(log.record_id).to eq(company.id.to_s)
  end
end 