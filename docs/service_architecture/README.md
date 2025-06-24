# Service Architecture Documentation

This folder contains comprehensive documentation for the B2B application's service architecture standards.

## Documents

### [SERVICE_ARCHITECTURE_STANDARD.md](../SERVICE_ARCHITECTURE_STANDARD.md)
**The main reference document** - Defines the standard architecture pattern that ALL services in the project must follow. This includes:
- Worker structure requirements
- Service structure requirements  
- Audit system integration
- Configuration management
- Error handling patterns
- Compliance requirements

### [DOMAIN_SERVICES_IMPLEMENTATION.md](../DOMAIN_SERVICES_IMPLEMENTATION.md)
**Implementation guide** - Specific details for the domain testing services that demonstrate the standard in practice:
- DNS, MX, and A Record testing services
- Individual domain queueing endpoints
- UI integration patterns
- Monitoring and troubleshooting

## Quick Reference

### Worker Pattern (REQUIRED)
```ruby
class ExampleWorker
  include Sidekiq::Worker
  sidekiq_options queue: "example_queue", retry: 3

  def perform(record_id)
    record = Model.find_by(id: record_id)
    return unless record

    service = ExampleService.new(record: record)
    service.call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Record ##{record_id} not found"
  rescue StandardError => e
    Rails.logger.error "Error processing record ##{record_id}: #{e.message}"
    raise
  end
end
```

### Service Pattern (REQUIRED)
```ruby
class ExampleService < ApplicationService
  def initialize(record: nil)
    super(service_name: "example_service", action: "process")
    @record = record
  end

  def call
    return test_single_record if record
    return {} unless service_active?
    # Batch processing logic
  end

  private

  def test_single_record
    # Create ServiceAuditLog
    # Perform business logic
    # Update record status
    # Update audit log with results
  end

  def service_active?
    ServiceConfiguration.active?(service_name)
  end
end
```

## Key Benefits

✅ **Consistency** - All services follow identical patterns  
✅ **Monitoring** - Centralized audit logging with rich metadata  
✅ **Reliability** - Proper error handling at all levels  
✅ **Flexibility** - Services work individually or in batches  
✅ **Configuration** - Global service activation control  

## Implementation Checklist

When creating new services:

- [ ] Worker follows exact pattern from standard
- [ ] Service inherits from `ApplicationService`
- [ ] Audit logging implemented with `ServiceAuditLog`
- [ ] Service configuration check with `ServiceConfiguration.active?()`
- [ ] Error handling at worker and service levels
- [ ] Tests for worker, service, and integration scenarios
- [ ] Documentation updated with new service details

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Controller    │───▶│     Worker      │───▶│     Service     │
│   (UI/API)      │    │   (Sidekiq)     │    │ (Business Logic)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ServiceAuditLog  │◀───│ServiceConfig    │◀───│  Domain Model   │
│  (Tracking)     │    │ (Activation)    │    │   (Data)        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Getting Started

1. Read the [SERVICE_ARCHITECTURE_STANDARD.md](../SERVICE_ARCHITECTURE_STANDARD.md) thoroughly
2. Review [DOMAIN_SERVICES_IMPLEMENTATION.md](../DOMAIN_SERVICES_IMPLEMENTATION.md) for practical examples
3. Follow the implementation checklist for new services
4. Ensure compliance with all requirements before deployment

## Questions?

Refer to the troubleshooting sections in the implementation guide, or check existing domain services for pattern examples.