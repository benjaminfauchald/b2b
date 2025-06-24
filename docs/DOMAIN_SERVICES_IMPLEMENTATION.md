# Domain Services Implementation Guide

## Overview

This document provides specific implementation details for the domain testing services that follow the established service architecture standard.

## Current Domain Services

### 1. DNS Testing Service
- **Service**: `DomainTestingService`
- **Worker**: `DomainDnsTestingWorker`
- **Queue**: `domain_dns_testing`
- **Purpose**: Tests DNS resolution for domains
- **Updates**: `domains.dns` column

### 2. MX Testing Service
- **Service**: `DomainMxTestingService`
- **Worker**: `DomainMxTestingWorker`
- **Queue**: `domain_mx_testing`
- **Purpose**: Tests MX record availability
- **Updates**: `domains.mx` column

### 3. A Record Testing Service
- **Service**: `DomainARecordTestingService`
- **Worker**: `DomainARecordTestingWorker`
- **Queue**: `DomainARecordTestingService`
- **Purpose**: Tests WWW A record resolution
- **Updates**: `domains.www` column

## Implementation Details

### Service Configuration

All domain services are configured in the database:

```ruby
# DNS Testing
ServiceConfiguration.create!(
  service_name: "domain_testing",
  active: true,
  refresh_interval_hours: 24
)

# MX Testing  
ServiceConfiguration.create!(
  service_name: "domain_mx_testing",
  active: true,
  refresh_interval_hours: 24
)

# A Record Testing
ServiceConfiguration.create!(
  service_name: "domain_a_record_testing",
  active: true,
  refresh_interval_hours: 24
)
```

### Domain Model Integration

The `Domain` model includes the `ServiceAuditable` concern:

```ruby
class Domain < ApplicationRecord
  include ServiceAuditable
  
  # Columns updated by services:
  # - dns (boolean)
  # - mx (boolean) 
  # - www (boolean)
  # - mx_error (string)
end
```

### Audit Tracking Pattern

Each service creates detailed audit logs:

```ruby
ServiceAuditLog.create!(
  auditable: domain,
  service_name: "domain_testing",
  operation_type: "test_dns",
  status: :pending,
  columns_affected: ["dns"],
  metadata: { domain_name: domain.domain },
  table_name: "domains",
  record_id: domain.id.to_s,
  started_at: Time.current
)
```

### Individual Domain Queueing

The controller provides endpoints for queueing individual domains:

```ruby
# POST /domains/:id/queue_single_dns
# POST /domains/:id/queue_single_mx  
# POST /domains/:id/queue_single_www
```

These endpoints:
1. Check service configuration
2. Create audit log for queueing action
3. Queue Sidekiq job
4. Return JSON response with job details

### UI Integration

The domain show page includes service queue buttons:

```erb
<%= render DomainServiceButtonComponent.new(domain: @domain, service: :dns) %>
<%= render DomainServiceButtonComponent.new(domain: @domain, service: :mx) %>
<%= render DomainServiceButtonComponent.new(domain: @domain, service: :www) %>
```

Each button:
- Shows current service status
- Allows manual queueing
- Updates in real-time via JavaScript
- Provides user feedback

## Service-Specific Implementation

### DNS Testing Service

```ruby
class DomainTestingService < ApplicationService
  def perform_dns_test
    resolver = Resolv::DNS.new
    records = {
      a: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::A).map(&:address),
      mx: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::MX).map(&:exchange),
      txt: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::TXT).map(&:strings).flatten
    }

    {
      status: records.values.any?(&:any?) ? "success" : "no_records",
      records: records
    }
  rescue Resolv::ResolvError => e
    {
      status: "error",
      records: { error: e.message }
    }
  end

  def update_domain_status(domain, result)
    case result[:status]
    when "success"
      domain.update_columns(dns: true)
    when "no_records", "error"
      domain.update_columns(dns: false)
    end
  end
end
```

### MX Testing Service

```ruby
class DomainMxTestingService < KafkaService
  def perform_mx_test(domain_name)
    start_time = Time.current
    resolver = Resolv::DNS.new
    begin
      Timeout.timeout(MX_TIMEOUT) do
        mx_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::MX)
        {
          status: mx_records.any? ? :success : :no_records,
          mx_records: mx_records.map { |mx| mx.exchange.to_s },
          duration: Time.current - start_time
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: :error,
        error: "DNS resolution failed",
        duration: Time.current - start_time
      }
    rescue Timeout::Error => e
      {
        status: :error,
        error: "DNS resolution timed out after #{MX_TIMEOUT} seconds",
        duration: Time.current - start_time
      }
    end
  end

  def update_domain_status(domain, result)
    case result[:status]
    when :success
      domain.update_columns(mx: true)
    when :no_records, :error, :timeout
      domain.update_columns(mx: false)
    end
  end
end
```

### A Record Testing Service

```ruby
class DomainARecordTestingService < ApplicationService
  def perform_a_record_test
    begin
      Timeout.timeout(DNS_TIMEOUT) do
        a_record = Resolv.getaddress("www.#{domain.domain}")
        {
          status: :success,
          a_record: a_record
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: :no_records,
        error: "A record resolution failed"
      }
    rescue Timeout::Error => e
      {
        status: :timeout,
        error: "A record resolution timed out after #{DNS_TIMEOUT} seconds"
      }
    end
  end

  def update_domain_status(domain, result)
    case result[:status]
    when :success
      domain.update_columns(www: true)
    when :no_records, :timeout
      domain.update_columns(www: false)
    end
  end
end
```

## Monitoring and Operations

### Checking Service Status

```ruby
# Check if services are active
ServiceConfiguration.active?("domain_testing")
ServiceConfiguration.active?("domain_mx_testing")
ServiceConfiguration.active?("domain_a_record_testing")

# View recent audit logs
ServiceAuditLog.where(service_name: "domain_testing").recent.limit(10)

# Check domains needing service
Domain.needing_service("domain_testing").count
```

### Manual Operations

```ruby
# Queue individual domain
DomainDnsTestingWorker.perform_async(domain.id)
DomainMxTestingWorker.perform_async(domain.id)
DomainARecordTestingWorker.perform_async(domain.id)

# Queue multiple domains
DomainTestingService.queue_100_domains
DomainMxTestingService.queue_100_domains
DomainARecordTestingService.queue_100_domains

# Run service directly
service = DomainTestingService.new(domain: domain)
result = service.call
```

### Performance Monitoring

```ruby
# Average execution times
ServiceAuditLog.where(service_name: "domain_testing")
              .where.not(execution_time_ms: nil)
              .average(:execution_time_ms)

# Success rates
total = ServiceAuditLog.where(service_name: "domain_testing").count
successful = ServiceAuditLog.where(service_name: "domain_testing", status: :success).count
success_rate = (successful.to_f / total * 100).round(2)
```

## Troubleshooting

### Common Issues

1. **Service Disabled**: Check `ServiceConfiguration.active?()` status
2. **Jobs Not Processing**: Verify Sidekiq workers are running
3. **Timeout Errors**: Check network connectivity and DNS resolution
4. **Audit Log Failures**: Verify required fields are present

### Debugging Commands

```bash
# Check Sidekiq queues
bundle exec sidekiq -q domain_dns_testing -q domain_mx_testing

# View Rails logs
tail -f log/development.log

# Check queue status
rails console
> require 'sidekiq/api'
> Sidekiq::Queue.new('domain_dns_testing').size
```

## Testing

### RSpec Examples

```ruby
# Worker spec
RSpec.describe DomainDnsTestingWorker do
  it "processes domain DNS testing" do
    domain = create(:domain)
    expect(DomainTestingService).to receive(:new).with(domain: domain).and_call_original
    described_class.new.perform(domain.id)
  end
end

# Service spec
RSpec.describe DomainTestingService do
  it "creates audit log for single domain test" do
    domain = create(:domain)
    service = described_class.new(domain: domain)
    
    expect { service.call }.to change(ServiceAuditLog, :count).by(1)
    
    audit_log = ServiceAuditLog.last
    expect(audit_log.service_name).to eq("domain_testing")
    expect(audit_log.auditable).to eq(domain)
  end
end
```

## Best Practices

1. **Always check service configuration** before processing
2. **Use audit system** for all operations tracking
3. **Handle timeouts gracefully** with appropriate error messages
4. **Store rich metadata** in audit logs for debugging
5. **Use update_columns()** for direct database updates to avoid callbacks
6. **Test both individual and batch processing** scenarios
7. **Monitor performance** via audit log execution times
8. **Follow consistent error handling** patterns across all services