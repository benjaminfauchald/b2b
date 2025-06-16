require 'rails_helper'

RSpec.describe ApplicationService, type: :service do
  # Create a test service class
  let(:test_service_class) do
    Class.new(ApplicationService) do
      attribute :test_param, :string
      
      def initialize(attributes = {})
        super(action: 'test_action', **attributes)
      end
      
      private
      
      def perform
        { result: 'success', test_param: test_param }
      end
    end
  end

  let(:failing_service_class) do
    Class.new(ApplicationService) do
      def initialize(attributes = {})
        super(**attributes)
      end
      
      private
      
      def perform
        raise StandardError, 'Service failed'
      end
    end
  end

  describe 'attributes' do
    it 'has service_name attribute' do
      service = ApplicationService.new
      expect(service.service_name).to eq('application_service')
    end

    it 'has action attribute with default' do
      service = ApplicationService.new
      expect(service.action).to eq('process')
    end

    it 'has batch_size attribute' do
      service = ApplicationService.new(batch_size: 500)
      expect(service.batch_size).to eq(500)
    end
  end

  describe 'validations' do
    it 'validates presence of service_name' do
      service = ApplicationService.new
      expect(service).not_to be_valid
      expect(service.errors[:service_name]).to include("can't be blank")
    end

    it 'validates service_name format' do
      service = ApplicationService.new(service_name: 'invalid name')
      expect(service).not_to be_valid
      expect(service.errors[:service_name]).to include('can only contain lowercase letters, numbers, and underscores')
    end

    it 'accepts valid service_name format' do
      service = ApplicationService.new(service_name: 'user_enhancement_service')
      expect(service).to be_valid
    end
  end

  describe '#call' do
    context 'with valid service' do
      let(:service) { test_service_class.new(test_param: 'test_value') }

      it 'validates before performing' do
        expect(service).to receive(:validate!).and_call_original
        service.call
      end

      it 'calls perform method' do
        expect(service).to receive(:perform).and_call_original
        result = service.call
        expect(result).to eq({ result: 'success', test_param: 'test_value' })
      end

      it 'returns result from perform' do
        result = service.call
        expect(result).to eq({ result: 'success', test_param: 'test_value' })
      end
    end

    context 'with invalid service' do
      let(:service) { ApplicationService.new }

      it 'raises validation error' do
        expect { service.call }.to raise_error(ActiveModel::ValidationError)
      end
    end

    context 'when perform raises error' do
      let(:service) { failing_service_class.new }

      it 'propagates the error' do
        expect { service.call }.to raise_error(StandardError, 'Service failed')
      end
    end
  end

  describe '#validate!' do
    it 'raises ValidationError when invalid' do
      service = ApplicationService.new
      expect { service.validate! }.to raise_error(ActiveModel::ValidationError)
    end

    it 'does not raise when valid' do
      service = ApplicationService.new(action: 'test_action')
      expect { service.validate! }.not_to raise_error
    end
  end

  describe '#configuration' do
    let!(:config) { create(:service_configuration, service_name: "application_service_#{SecureRandom.hex(8)}") }
    let(:service) { test_service_class.new }

    it 'returns service configuration' do
      expect(service.configuration.service_name).to start_with('application_service_')
    end

    it 'returns nil for non-existent service' do
      service = ApplicationService.new
      expect(service.configuration).to be_nil
    end
  end

  describe '#batch_process' do
    let(:users) { create_list(:user, 3) }
    let(:service) { test_service_class.new }

    it 'processes records in batches with audit logging' do
      processed_users = []
      
      service.batch_process(users) do |user, audit_log|
        processed_users << user
        expect(audit_log).to be_a(ServiceAuditLog)
        expect(audit_log.service_name).to eq('test_service')
        audit_log.mark_success!
      end

      expect(processed_users).to match_array(users)
      expect(ServiceAuditLog.count).to eq(3)
    end

    it 'handles batch_size configuration' do
      service = test_service_class.new(batch_size: 2)
      
      # Mock the batch_audit method to verify batch_size is used
      expect(ServiceAuditLog).to receive(:batch_audit).with(
        users, 
        service_name: 'test_service', 
        action: 'test_action',
        batch_size: 2
      ).and_call_original

      service.batch_process(users) do |user, audit_log|
        audit_log.mark_success!
      end
    end
  end

  describe 'class methods' do
    describe '.call' do
      it 'creates instance and calls it' do
        result = test_service_class.call(test_param: 'class_method_test')
        expect(result).to eq({ result: 'success', test_param: 'class_method_test' })
      end

      it 'passes all arguments to new' do
        expect(test_service_class).to receive(:new).with(test_param: 'test').and_call_original
        test_service_class.call(test_param: 'test')
      end
    end
  end

  describe 'protected methods' do
    let(:service) { test_service_class.new }

    describe '#perform' do
      it 'raises NotImplementedError in base class' do
        base_service = ApplicationService.new
        expect { base_service.send(:perform) }.to raise_error(NotImplementedError)
      end
    end

    describe '#log_service_start' do
      it 'logs service start' do
        expect(Rails.logger).to receive(:info).with(/Starting service: test_service/)
        service.send(:log_service_start)
      end
    end

    describe '#log_service_completion' do
      it 'logs service completion' do
        expect(Rails.logger).to receive(:info).with(/Completed service: test_service/)
        service.send(:log_service_completion, { result: 'success' })
      end
    end

    describe '#log_service_error' do
      let(:error) { StandardError.new('Test error') }

      it 'logs service error' do
        expect(Rails.logger).to receive(:error).with(/Service failed: test_service/)
        service.send(:log_service_error, error)
      end
    end
  end

  describe 'integration with ServiceConfiguration' do
    let!(:config) do
      create(:service_configuration, 
             service_name: "integration_test_#{SecureRandom.hex(8)}",
             batch_size: 100,
             settings: { 'timeout' => 30 })
    end

    let(:integration_service_class) do
      Class.new(ApplicationService) do
        def initialize(attributes = {})
          super(service_name: 'integration_test', **attributes)
        end
        
        private
        
        def perform
          {
            batch_size: batch_size || configuration&.batch_size,
            timeout: configuration&.get_setting('timeout')
          }
        end
      end
    end

    it 'uses configuration values when not explicitly set' do
      service = integration_service_class.new
      result = service.call
      
      expect(result[:batch_size]).to eq(100)
      expect(result[:timeout]).to eq(30)
    end

    it 'allows overriding configuration values' do
      service = integration_service_class.new(batch_size: 50)
      result = service.call
      
      expect(result[:batch_size]).to eq(50)
      expect(result[:timeout]).to eq(30)
    end
  end
end 