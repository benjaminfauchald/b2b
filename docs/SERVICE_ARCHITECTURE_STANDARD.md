# Service Architecture Standard

## Overview

This document defines the standard architecture pattern for all services in the B2B application. This pattern ensures consistency, maintainability, and proper audit tracking across all background processing tasks.

## Architecture Components

### 1. Service Layer (`app/services/`)
Services are the core business logic containers that handle all domain-specific operations.

### 2. Worker Layer (`app/workers/`)
Workers are lightweight job processors that handle async execution via Sidekiq.

### 3. Audit System (`ServiceAuditLog`)
Centralized tracking system that logs all service operations with detailed metadata.

### 4. Configuration System (`ServiceConfiguration`)
Global service activation and configuration management.

## Standard Pattern

### Worker Structure

All workers MUST follow this exact pattern:

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
    Rails.logger.error "Error processing record ##{record_id}: #{e.message}"
    raise
  end
end
```

### Service Structure

All services MUST inherit from `ApplicationService` and follow this pattern:

```ruby
class ExampleService < ApplicationService
  attr_reader :record, :batch_size

  def initialize(record: nil, batch_size: 100)
    super(service_name: "example_service", action: "process")
    @record = record
    @batch_size = batch_size
  end

  def call
    return test_single_record if record
    return { processed: 0, successful: 0, failed: 0, errors: 0 } unless service_active?
    test_records_in_batches(Model.needing_service(service_name))
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
        columns_affected: ["field_name"],
        metadata: { record_name: record.name },
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
          test_result: result[:status]
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
            field_status: record.field_name
          })
        )
      end
      raise e
    end
  end

  def perform_business_logic
    # Implement your business logic here
    {
      status: :success,
      data: "example"
    }
  end

  def update_record_status(record, result)
    case result[:status]
    when :success
      record.update_columns(field_name: true)
    when :failed, :timeout
      record.update_columns(field_name: false)
    end
  end

  def service_active?
    ServiceConfiguration.active?(service_name)
  end
end
```

## Key Principles

### 1. Single Responsibility
- **Workers**: Handle job execution and error logging only
- **Services**: Handle business logic and audit tracking only

### 2. Audit System Integration
- All operations MUST be tracked via `ServiceAuditLog`
- Services handle audit logging, not workers
- Rich metadata stored for debugging and monitoring

### 3. Error Handling
- Workers handle job-level errors
- Services handle business logic errors
- Both levels log appropriately

### 4. Configuration Management
- All services check `ServiceConfiguration.active?()` before processing
- Global configuration controls service activation

### 5. Consistent Patterns
- All workers follow identical structure
- All services inherit from `ApplicationService`
- Consistent naming conventions

## Benefits

### Consistency
- Predictable code structure across all services
- Easy to understand and maintain
- Standardized error handling

### Monitoring
- Centralized audit logging in `ServiceAuditLog`
- Rich metadata for debugging
- Performance tracking with execution times

### Flexibility
- Services can be called directly or via workers
- Global service activation control
- Easy to add new services following the pattern

### Reliability
- Proper error handling at all levels
- Audit trail for all operations
- Configurable retry policies

## Implementation Examples

The following services follow this standard:

- `DomainTestingService` + `DomainDnsTestingWorker`
- `DomainMxTestingService` + `DomainMxTestingWorker`  
- `DomainARecordTestingService` + `DomainARecordTestingWorker`

## Migration Guide

When updating existing services to follow this standard:

1. **Simplify the worker** to only call the service
2. **Move audit logic** from worker to service
3. **Add proper audit logging** with `ServiceAuditLog`
4. **Implement configuration checks** with `ServiceConfiguration.active?()`
5. **Follow error handling patterns** at both worker and service levels

## Compliance Requirements

All new services MUST:
- [ ] Follow the worker pattern exactly
- [ ] Inherit from `ApplicationService`
- [ ] Implement proper audit logging
- [ ] Check service configuration before processing
- [ ] Handle single record and batch processing
- [ ] Include comprehensive error handling
- [ ] Use `update_columns()` for direct database updates
- [ ] Store rich metadata in audit logs

## Testing Requirements

All services MUST include:
- Worker specs testing job execution
- Service specs testing business logic
- Integration specs testing end-to-end functionality
- Audit logging verification
- Error handling verification

## Configuration

Add service configuration via Rails console:

```ruby
ServiceConfiguration.create!(
  service_name: "example_service",
  active: true,
  refresh_interval_hours: 24
)
```

## Monitoring

Monitor services via:
- `ServiceAuditLog` for operation history
- Sidekiq web interface for job status
- Rails logs for error tracking
- `ServiceConfiguration` for activation status