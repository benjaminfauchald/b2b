# SCT Pattern Compliance Guide

## Overview

The **SCT (Service-Controller-Template)** pattern ensures consistency, maintainability, and proper audit tracking across all services in our Rails application. This document outlines the compliance requirements and enforcement mechanisms.

## SCT Pattern Requirements

### 1. Service Inheritance

All services MUST inherit from `ApplicationService`:

```ruby
class MyService < ApplicationService
  # implementation
end
```

### 2. Required Constructor Pattern

Services MUST call `super()` with `service_name` and `action`:

```ruby
def initialize(entity:, **options)
  @entity = entity
  super(service_name: "my_service", action: "process", **options)
end
```

### 3. Required Methods

All services MUST implement these methods:

#### `#perform`
Main business logic method:

```ruby
def perform
  return error_result("Service is disabled") unless service_active?
  
  audit_service_operation(@entity) do |audit_log|
    # Business logic here
    # Add metadata: audit_log.add_metadata(key: value)
    success_result("Operation completed", data: result)
  end
rescue StandardError => e
  error_result("Service error: #{e.message}")
end
```

#### `#service_active?` (private)
Check service configuration:

```ruby
private

def service_active?
  config = ServiceConfiguration.find_by(service_name: service_name)
  return false unless config
  config.active?
end
```

#### `#success_result` and `#error_result` (private)
Standardized result objects:

```ruby
def success_result(message, data = {})
  OpenStruct.new(
    success?: true,
    message: message,
    data: data,
    error: nil
  )
end

def error_result(message, data = {})
  OpenStruct.new(
    success?: false,
    message: nil,
    error: message,
    data: data
  )
end
```

### 4. Audit Logging

Services MUST use `audit_service_operation` instead of manual `ServiceAuditLog.create!`:

```ruby
# ✅ GOOD
audit_service_operation(@entity) do |audit_log|
  # Business logic
  audit_log.add_metadata(processed_count: count)
  success_result("Completed")
end

# ❌ BAD
audit_log = ServiceAuditLog.create!(...)
# manual audit handling
```

### 5. Service Configuration

Each service SHOULD have a corresponding `ServiceConfiguration` record:

```ruby
ServiceConfiguration.create!(
  service_name: "my_service",
  active: true,
  refresh_interval_hours: 24,
  batch_size: 100,
  description: "Service description"
)
```

## Enforcement Mechanisms

### 1. Runtime Validation

`ApplicationService` includes automatic SCT compliance validation:

```ruby
def validate_sct_compliance!
  # Checks for required methods
  # Validates service configuration
  # Logs warnings for missing patterns
end
```

### 2. RuboCop Custom Cop

Add to `.rubocop.yml`:

```yaml
inherit_from: .rubocop_sct.yml
```

Run compliance check:

```bash
bundle exec rubocop --config .rubocop_sct.yml app/services/
```

### 3. Rake Tasks

Check compliance for all services:

```bash
# Full compliance check
rake sct:full_check

# Just check compliance
rake sct:compliance

# Generate missing ServiceConfiguration records
rake sct:generate_configs

# Run SCT compliance tests
rake sct:test
```

### 4. RSpec Shared Examples

Include in service specs:

```ruby
RSpec.describe MyService, type: :service do
  include_examples 'SCT compliant service', MyService, 'my_service', 'process'
  include_examples 'SCT audit compliant service', 'my_service', :my_entity
  
  # Service-specific tests...
end
```

### 5. GitHub Actions

Automatic compliance checking on PRs:
- `.github/workflows/sct_compliance.yml`
- Runs on all service file changes
- Comments on PRs with compliance status
- Blocks merging if non-compliant

## Testing Requirements

### Required Test Coverage

Each service MUST have tests covering:

1. **Successful operation with audit log creation**
2. **Service configuration active/inactive states**
3. **Error handling and audit logging**
4. **Metadata inclusion in audit logs**
5. **Execution time tracking**

### Example Test Structure

```ruby
describe '#perform' do
  context 'when service configuration is active' do
    before do
      create(:service_configuration, service_name: 'my_service', active: true)
    end

    it 'creates a successful audit log' do
      expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.service_name).to eq('my_service')
      expect(audit_log.status).to eq('success')
      expect(audit_log.execution_time_ms).to be_present
    end
  end

  context 'when service configuration is inactive' do
    before do
      create(:service_configuration, service_name: 'my_service', active: false)
    end

    it 'does not perform operation' do
      result = service.perform
      expect(result.success?).to be false
      expect(result.error).to eq('Service is disabled')
    end
  end
end
```

## Migration Guide

### Converting Non-Compliant Services

1. **Update inheritance and constructor**:
   ```ruby
   # Before
   class MyService
     def initialize(entity)
       @entity = entity
     end
   end

   # After
   class MyService < ApplicationService
     def initialize(entity:, **options)
       @entity = entity
       super(service_name: "my_service", action: "process", **options)
     end
   end
   ```

2. **Replace manual audit logging**:
   ```ruby
   # Before
   audit_log = ServiceAuditLog.create!(...)
   begin
     # logic
     audit_log.mark_success!
   rescue => e
     audit_log.mark_failed!(e.message)
   end

   # After
   audit_service_operation(@entity) do |audit_log|
     # logic
     audit_log.add_metadata(key: value)
     success_result("Completed")
   end
   ```

3. **Add required methods**:
   ```ruby
   private

   def service_active?
     config = ServiceConfiguration.find_by(service_name: service_name)
     return false unless config
     config.active?
   end

   def success_result(message, data = {})
     OpenStruct.new(success?: true, message: message, data: data, error: nil)
   end

   def error_result(message, data = {})
     OpenStruct.new(success?: false, message: nil, error: message, data: data)
   end
   ```

## Common Pitfalls

### ❌ Manual Audit Log Creation
```ruby
# Don't do this
ServiceAuditLog.create!(auditable: entity, service_name: service_name, ...)
```

### ❌ Missing Service Configuration Check
```ruby
# Don't skip this check
def perform
  # Missing: return error_result("Service is disabled") unless service_active?
  # business logic
end
```

### ❌ Inconsistent Result Objects
```ruby
# Don't return raw values
def perform
  return true  # Bad
  return { success: true }  # Bad
  return success_result("Completed")  # Good
end
```

### ❌ Missing Required Methods
```ruby
# Don't forget to implement
def service_active?; end
def success_result(message, data = {}); end
def error_result(message, data = {}); end
```

## Benefits of SCT Compliance

1. **Consistent Audit Trails**: All service operations are properly logged
2. **Standardized Error Handling**: Uniform error patterns across services
3. **Configuration Management**: Centralized service activation/deactivation
4. **Testability**: Shared test patterns ensure comprehensive coverage
5. **Maintainability**: Predictable service structure for all developers
6. **Monitoring**: Standard metrics and logging for operations

## Support

For questions about SCT compliance:
1. Check this documentation
2. Review existing compliant services as examples
3. Run `rake sct:compliance` to identify specific issues
4. Use shared RSpec examples for testing patterns