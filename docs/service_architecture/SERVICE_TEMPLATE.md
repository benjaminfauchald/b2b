# Service Template

Use this template when creating new services to ensure compliance with the architecture standard.

## Files to Create

### 1. Service File: `app/services/example_service.rb`

```ruby
require "timeout" # If needed for external API calls

class ExampleService < ApplicationService
  attr_reader :record, :batch_size, :max_retries

  # Define any timeout constants
  API_TIMEOUT = 5 # seconds

  def initialize(record: nil, batch_size: 100, max_retries: 3)
    super(service_name: "example_service", action: "process")
    @record = record
    @batch_size = batch_size
    @max_retries = max_retries
  end

  def call
    return test_single_record if record
    return { processed: 0, successful: 0, failed: 0, errors: 0 } unless service_active?
    test_records_in_batches(Model.needing_service(service_name))
  end

  # Legacy class methods for backward compatibility (if needed)
  def self.process_record(record)
    new(record: record).call
  end

  def self.queue_all_records
    records = Model.needing_service("example_service")
    count = 0

    records.find_each do |record|
      ExampleWorker.perform_async(record.id)
      count += 1
    end

    count
  end

  def self.queue_batch_records(limit = 100)
    records = Model.needing_service("example_service").limit(limit)
    count = 0

    records.each do |record|
      ExampleWorker.perform_async(record.id)
      count += 1
    end

    count
  end

  private

  def test_single_record
    audit_log = nil
    begin
      audit_log = ServiceAuditLog.create!(
        auditable: record,
        service_name: service_name,
        operation_type: action,
        status: :pending,
        columns_affected: ["field_name"], # Update with actual fields
        metadata: { record_identifier: record.name_or_id },
        table_name: record.class.table_name,
        record_id: record.id.to_s,
        started_at: Time.current
      )

      result = perform_business_logic
      update_record_status(record, result)
      
      audit_log.update!(
        status: :success,
        completed_at: Time.current,
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
        metadata: audit_log.metadata.merge({
          field_status: record.field_name,
          operation_result: result[:status],
          # Add any relevant result data
        })
      )
      
      result
    rescue StandardError => e
      if audit_log
        audit_log.update!(
          status: :failed,
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
          metadata: audit_log.metadata.merge({
            error: e.message,
            error_type: e.class.name,
            field_status: record.field_name
          })
        )
      end
      raise e
    end
  end

  def test_records_in_batches(records)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    
    records.find_each(batch_size: batch_size) do |record|
      audit_log = nil
      begin
        audit_log = ServiceAuditLog.create!(
          auditable: record,
          service_name: service_name,
          operation_type: action,
          status: :pending,
          columns_affected: ["field_name"],
          metadata: { record_identifier: record.name_or_id },
          table_name: record.class.table_name,
          record_id: record.id.to_s,
          started_at: Time.current
        )
        
        result = perform_business_logic
        
        if result[:status] == :success
          update_record_status(record, result)
          audit_log.update!(
            status: :success,
            completed_at: Time.current,
            execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
            metadata: audit_log.metadata.merge({
              field_status: record.field_name,
              operation_result: result[:status]
            })
          )
          results[:successful] += 1
        else
          update_record_status(record, result)
          audit_log.update!(
            status: :failed,
            completed_at: Time.current,
            execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
            metadata: audit_log.metadata.merge({
              error: result[:error] || "Operation failed",
              field_status: record.field_name
            })
          )
          results[:failed] += 1
        end
        results[:processed] += 1
      rescue StandardError => e
        results[:errors] += 1
        if audit_log
          audit_log.update!(
            status: :failed,
            completed_at: Time.current,
            execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round,
            metadata: audit_log.metadata.merge({
              error: e.message,
              error_type: e.class.name
            })
          )
        end
      end
    end
    results
  end

  def perform_business_logic
    # Implement your business logic here
    # Example API call or data processing
    begin
      Timeout.timeout(API_TIMEOUT) do
        # Your logic here
        # external_api_call(record.identifier)
        
        {
          status: :success,
          data: "processed_data"
        }
      end
    rescue Timeout::Error => e
      {
        status: :timeout,
        error: "Operation timed out after #{API_TIMEOUT} seconds"
      }
    rescue StandardError => e
      {
        status: :error,
        error: e.message
      }
    end
  end

  def update_record_status(record, result)
    case result[:status]
    when :success
      record.update_columns(field_name: true)
    when :timeout, :error
      record.update_columns(field_name: false)
    end
  end

  def service_active?
    ServiceConfiguration.active?(service_name)
  end
end
```

### 2. Worker File: `app/workers/example_worker.rb`

```ruby
class ExampleWorker
  include Sidekiq::Worker

  sidekiq_options queue: "example_queue", retry: 3

  def perform(record_id)
    record = Model.find_by(id: record_id)
    return unless record

    # Use audit system for tracking - the service handles all audit logging
    service = ExampleService.new(record: record)
    service.call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Record ##{record_id} not found for example service"
  rescue StandardError => e
    Rails.logger.error "Error processing record ##{record_id} in example service: #{e.message}"
    raise
  end
end
```

### 3. Service Configuration (via Rails console)

```ruby
ServiceConfiguration.create!(
  service_name: "example_service",
  active: true,
  refresh_interval_hours: 24
)
```

### 4. Controller Actions (if needed for individual queueing)

```ruby
# In your controller
def queue_single_example
  unless ServiceConfiguration.active?("example_service")
    render json: { success: false, message: "Example service is disabled" }
    return
  end

  begin
    # Create service audit log for queueing action
    audit_log = ServiceAuditLog.create!(
      auditable: @record,
      service_name: "example_service",
      operation_type: "queue_individual",
      status: "pending",
      table_name: @record.class.table_name,
      record_id: @record.id.to_s,
      columns_affected: ["field_name"],
      metadata: {
        action: "manual_queue",
        user_id: current_user.id,
        timestamp: Time.current
      }
    )

    job_id = ExampleWorker.perform_async(@record.id)

    render json: {
      success: true,
      message: "Record queued for example service",
      record_id: @record.id,
      service: "example",
      job_id: job_id,
      worker: "ExampleWorker",
      audit_log_id: audit_log.id
    }
  rescue => e
    render json: {
      success: false,
      message: "Failed to queue record for example service: #{e.message}"
    }
  end
end
```

### 5. Route (if needed)

```ruby
# In config/routes.rb
resources :models do
  member do
    post :queue_single_example
  end
end
```

### 6. Tests

#### Worker Spec: `spec/workers/example_worker_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe ExampleWorker, type: :worker do
  let(:record) { create(:model) }
  
  describe '#perform' do
    it 'processes record with example service' do
      expect_any_instance_of(ExampleService).to receive(:call)
      described_class.new.perform(record.id)
    end

    it 'handles record not found gracefully' do
      expect(Rails.logger).to receive(:error).with(/Record #999 not found/)
      described_class.new.perform(999)
    end

    it 'logs and re-raises service errors' do
      allow_any_instance_of(ExampleService).to receive(:call).and_raise(StandardError, "Service error")
      expect(Rails.logger).to receive(:error).with(/Error processing record/)
      
      expect {
        described_class.new.perform(record.id)
      }.to raise_error(StandardError, "Service error")
    end
  end
end
```

#### Service Spec: `spec/services/example_service_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe ExampleService, type: :service do
  let(:record) { create(:model) }
  let(:service) { described_class.new(record: record) }

  before do
    create(:service_configuration, service_name: "example_service", active: true)
  end

  describe '#call' do
    context 'with single record' do
      it 'creates audit log' do
        expect { service.call }.to change(ServiceAuditLog, :count).by(1)
        
        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq("example_service")
        expect(audit_log.auditable).to eq(record)
        expect(audit_log.status).to eq("success")
      end

      it 'updates record status on success' do
        service.call
        expect(record.reload.field_name).to eq(true)
      end

      it 'handles errors gracefully' do
        allow(service).to receive(:perform_business_logic).and_raise(StandardError, "Test error")
        
        expect { service.call }.to raise_error(StandardError, "Test error")
        
        audit_log = ServiceAuditLog.last
        expect(audit_log.status).to eq("failed")
        expect(audit_log.metadata["error"]).to eq("Test error")
      end
    end

    context 'when service is inactive' do
      before do
        ServiceConfiguration.find_by(service_name: "example_service").update!(active: false)
      end

      it 'returns empty result without processing' do
        result = described_class.new.call
        expect(result).to eq({ processed: 0, successful: 0, failed: 0, errors: 0 })
      end
    end
  end
end
```

## Customization Points

1. **Replace `example` with your actual service name** throughout
2. **Update `Model` with your actual model class**
3. **Modify `field_name` to match the actual field being updated**
4. **Implement actual business logic** in `perform_business_logic`
5. **Add any service-specific attributes** to the constructor
6. **Customize timeout values** and error handling as needed
7. **Update metadata fields** to include relevant information
8. **Adjust queue names** and retry policies as appropriate

## Checklist

Before deploying your new service:

- [ ] Service inherits from `ApplicationService`
- [ ] Worker follows exact pattern
- [ ] Audit logging implemented
- [ ] Service configuration check added
- [ ] Error handling at both worker and service levels
- [ ] Tests for worker and service
- [ ] Integration test for end-to-end functionality
- [ ] Documentation updated
- [ ] Service configuration created in database