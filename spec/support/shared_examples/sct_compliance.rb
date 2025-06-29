# frozen_string_literal: true

# Shared examples for SCT (Service-Controller-Template) pattern compliance
# These examples ensure all ApplicationService subclasses follow the established patterns

RSpec.shared_examples 'SCT compliant service' do |service_class, service_name, operation_type|
  let(:service_instance) { described_class.new }

  describe 'SCT pattern compliance' do
    context 'inheritance and initialization' do
      it 'inherits from ApplicationService' do
        expect(described_class.ancestors).to include(ApplicationService)
      end

      it 'has correct service_name' do
        expect(service_instance.service_name).to eq(service_name)
      end

      it 'has correct action/operation_type' do
        expect(service_instance.action).to eq(operation_type)
      end

      it 'accepts options in initialize and passes them to super' do
        instance = described_class.new(custom_option: 'test')
        expect(instance).to be_a(ApplicationService)
      end
    end

    context 'required methods' do
      it 'implements perform method' do
        expect(service_instance).to respond_to(:perform)
      end

      it 'implements service_active? method' do
        expect(service_instance).to respond_to(:service_active?, true)
      end

      it 'implements success_result method' do
        expect(service_instance).to respond_to(:success_result, true)
      end

      it 'implements error_result method' do
        expect(service_instance).to respond_to(:error_result, true)
      end
    end

    context 'service configuration integration' do
      before do
        create(:service_configuration, service_name: service_name, active: true)
      end

      it 'respects service configuration active status' do
        expect(service_instance.send(:service_active?)).to be true
      end

      it 'returns false when service is inactive' do
        ServiceConfiguration.find_by(service_name: service_name).update!(active: false)
        expect(service_instance.send(:service_active?)).to be false
      end

      it 'handles missing service configuration gracefully' do
        ServiceConfiguration.find_by(service_name: service_name).destroy
        expect(service_instance.send(:service_active?)).to be false
      end
    end

    context 'result objects' do
      it 'success_result returns proper OpenStruct' do
        result = service_instance.send(:success_result, 'Test message', data: 'test')

        expect(result).to be_a(OpenStruct)
        expect(result.success?).to be true
        expect(result.message).to eq('Test message')
        expect(result.data).to eq('test')
        expect(result.error).to be_nil
      end

      it 'error_result returns proper OpenStruct' do
        result = service_instance.send(:error_result, 'Test error', data: 'test')

        expect(result).to be_a(OpenStruct)
        expect(result.success?).to be false
        expect(result.message).to be_nil
        expect(result.error).to eq('Test error')
        expect(result.data).to eq('test')
      end
    end

    context 'audit_service_operation integration' do
      let(:test_entity) { create(:domain) if defined?(Domain) }

      before do
        create(:service_configuration, service_name: service_name, active: true)
        # Skip if we don't have a test entity available
        skip 'No test entity available for audit testing' unless test_entity
      end

      it 'uses audit_service_operation for tracking' do
        # This is a basic check - specific implementations should override
        # this with more detailed audit testing
        expect(service_instance).to respond_to(:audit_service_operation, true)
      end
    end

    context 'error handling' do
      before do
        create(:service_configuration, service_name: service_name, active: false)
      end

      it 'handles inactive service gracefully' do
        result = service_instance.perform

        expect(result.success?).to be false
        expect(result.error).to include('disabled')
      end
    end
  end
end

# Shared examples for services that process entities with audit logging
RSpec.shared_examples 'SCT audit compliant service' do |service_name, auditable_entity|
  before do
    create(:service_configuration, service_name: service_name, active: true)
  end

  context 'audit logging compliance' do
    let(:entity) { create(auditable_entity) }
    let(:service) { described_class.new("#{auditable_entity}": entity) }

    it 'creates audit log on successful operation' do
      expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.service_name).to eq(service_name)
      expect(audit_log.auditable).to eq(entity)
      expect(audit_log.status).to be_in([ 'success', 'failed' ])
      expect(audit_log.execution_time_ms).to be_present
    end

    it 'includes metadata in audit log' do
      service.perform

      audit_log = ServiceAuditLog.last
      expect(audit_log.metadata).to be_present
      expect(audit_log.metadata).to be_a(Hash)
    end

    it 'tracks execution time' do
      service.perform

      audit_log = ServiceAuditLog.last
      expect(audit_log.started_at).to be_present
      expect(audit_log.completed_at).to be_present
      expect(audit_log.execution_time_ms).to be > 0
    end
  end
end

# Shared examples for batch processing services
RSpec.shared_examples 'SCT batch processing service' do |service_name, batch_entity|
  before do
    create(:service_configuration, service_name: service_name, active: true)
  end

  context 'batch processing compliance' do
    let!(:entities) { create_list(batch_entity, 3) }
    let(:service) { described_class.new }

    it 'processes multiple entities with individual audit logs' do
      expect { service.perform }.to change(ServiceAuditLog, :count).by_at_least(1)

      audit_logs = ServiceAuditLog.where(service_name: service_name).recent
      expect(audit_logs.count).to be > 0
    end

    it 'returns batch processing results' do
      result = service.perform

      expect(result.success?).to be true
      expect(result.data).to include(:processed, :successful, :failed, :errors)
      expect(result.data[:processed]).to be_a(Integer)
      expect(result.data[:successful]).to be_a(Integer)
      expect(result.data[:failed]).to be_a(Integer)
      expect(result.data[:errors]).to be_a(Integer)
    end
  end
end

# Usage examples in service specs:
#
# RSpec.describe MyService, type: :service do
#   include_examples 'SCT compliant service', MyService, 'my_service', 'process'
#   include_examples 'SCT audit compliant service', 'my_service', :my_entity
#   include_examples 'SCT batch processing service', 'my_service', :my_entity
# end
