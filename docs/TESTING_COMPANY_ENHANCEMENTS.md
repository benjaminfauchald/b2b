# Testing Company Enhancement Services

This guide explains how to test the company enhancement services implementation.

## 1. Unit Tests (RSpec)

Run all tests:
```bash
bundle exec rspec
```

Run specific service tests:
```bash
# Test individual services
bundle exec rspec spec/services/company_financial_data_service_spec.rb
bundle exec rspec spec/services/company_web_discovery_service_spec.rb
bundle exec rspec spec/services/company_linkedin_discovery_service_spec.rb
bundle exec rspec spec/services/company_employee_discovery_service_spec.rb

# Test workers
bundle exec rspec spec/workers/company_financial_data_worker_spec.rb
bundle exec rspec spec/workers/company_web_discovery_worker_spec.rb
bundle exec rspec spec/workers/company_linkedin_discovery_worker_spec.rb
bundle exec rspec spec/workers/company_employee_discovery_worker_spec.rb

# Test controller
bundle exec rspec spec/controllers/companies_controller_spec.rb
```

## 2. Manual Testing in Console

### Start Rails Console
```bash
rails console
```

### Create Test Company
```ruby
company = Company.create!(
  registration_number: "123456789",
  company_name: "Test Company AS",
  organization_form_code: "AS",
  employee_count: 100,
  website: "https://example.com"
)
```

### Test Individual Services

#### Financial Data Service
```ruby
service = CompanyFinancialDataService.new(company)
result = service.perform
puts result.success? ? "Success: #{result.message}" : "Failed: #{result.error}"

# Check updated data
company.reload
puts "Revenue: #{company.revenue}"
puts "Profit: #{company.profit}"
puts "Total Assets: #{company.total_assets}"
```

#### Web Discovery Service
```ruby
service = CompanyWebDiscoveryService.new(company)
result = service.perform

# Check discovered web pages
company.reload
puts "Web pages: #{company.web_pages}"
```

#### LinkedIn Discovery Service
```ruby
service = CompanyLinkedinDiscoveryService.new(company)
result = service.perform

# Check LinkedIn URL
company.reload
puts "LinkedIn: #{company.linkedin_url}"
```

#### Employee Discovery Service
```ruby
service = CompanyEmployeeDiscoveryService.new(company)
result = service.perform

# Check employee data
company.reload
puts "Employees: #{company.employees_data}"
```

### Check Service Audit Logs
```ruby
# View all audit logs for a company
ServiceAuditLog.where(auditable: company).order(created_at: :desc).each do |log|
  puts "#{log.service_name}: #{log.status} - #{log.execution_time_ms}ms"
end

# Check specific service logs
ServiceAuditLog.where(auditable: company, service_name: 'company_financial_data').last
```

## 3. Testing Background Jobs

### Start Sidekiq (in separate terminal)
```bash
bundle exec sidekiq
```

### Queue Jobs from Console
```ruby
# Queue individual jobs
CompanyFinancialDataWorker.perform_async(company.id)
CompanyWebDiscoveryWorker.perform_async(company.id)
CompanyLinkedinDiscoveryWorker.perform_async(company.id)
CompanyEmployeeDiscoveryWorker.perform_async(company.id)

# Check queue sizes
require 'sidekiq/api'
Sidekiq::Queue.new('company_financial_data').size
Sidekiq::Queue.new('company_web_discovery').size
```

## 4. Testing Web Interface

### Start Rails Server
```bash
PORT=3000 rails server
```

### Test Company Enhancement Features

1. **View Companies List**
   - Navigate to http://localhost:3000/companies
   - You should see the enhancement queue management interface

2. **Queue Enhancement Services**
   - Click on "Queue" buttons for individual services
   - Use "Queue All" to queue all services for companies needing updates

3. **View Company Details**
   - Click on a company name to view details
   - Check the "Enhancement Status" section
   - View financial data if available

4. **Test Queue Management**
   ```bash
   # Queue financial data for 100 companies
   curl -X POST http://localhost:3000/companies/queue_financial_data?count=100
   
   # Queue all services
   curl -X POST http://localhost:3000/companies/queue_all_enhancements?count=50
   
   # Check queue status
   curl http://localhost:3000/companies/enhancement_queue_status
   ```

## 5. Testing Service Configuration

### Check Service Configurations
```ruby
ServiceConfiguration.where(service_name: ServiceConfiguration.pluck(:service_name).grep(/^company_/)).each do |config|
  puts "#{config.service_name}: Active=#{config.active?}, Interval=#{config.refresh_interval_hours}h"
end
```

### Disable/Enable Services
```ruby
# Disable a service
ServiceConfiguration.find_by(service_name: 'company_financial_data').update!(active: false)

# Enable a service
ServiceConfiguration.find_by(service_name: 'company_financial_data').update!(active: true)
```

## 6. Performance Testing

### Test Bulk Processing
```ruby
# Create multiple companies
companies = 10.times.map do |i|
  Company.create!(
    registration_number: "99900#{i.to_s.rjust(4, '0')}",
    company_name: "Test Company #{i} AS",
    organization_form_code: "AS"
  )
end

# Queue all for processing
companies.each do |company|
  CompanyFinancialDataWorker.perform_async(company.id)
end

# Monitor processing
loop do
  queue = Sidekiq::Queue.new('company_financial_data')
  puts "Queue size: #{queue.size}"
  break if queue.size == 0
  sleep 2
end
```

## 7. Testing Error Scenarios

### Test Service Failures
```ruby
# Test with invalid registration number
company = Company.create!(registration_number: "INVALID", company_name: "Invalid Company")
service = CompanyFinancialDataService.new(company)
result = service.perform
puts "Expected failure: #{result.error}"

# Check audit log for failure
log = ServiceAuditLog.where(auditable: company).last
puts "Status: #{log.status}, Error: #{log.error_message}"
```

## 8. Run Test Script

Execute the provided test script:
```bash
rails runner test_company_enhancements.rb
```

## 9. Monitoring

### Check Service Health
```ruby
# Companies needing service
Company.needs_service('company_financial_data').count

# Recent service runs
LatestServiceRun.where(service_name: 'company_financial_data').order(run_at: :desc).limit(10)

# Service success rate
total = ServiceAuditLog.where(service_name: 'company_financial_data').count
success = ServiceAuditLog.where(service_name: 'company_financial_data', status: 'success').count
puts "Success rate: #{(success.to_f / total * 100).round(2)}%"
```

## 10. Cleanup Test Data

```ruby
# Remove test companies
Company.where("company_name LIKE 'Test%'").destroy_all

# Clear audit logs for test companies
ServiceAuditLog.where(auditable_type: 'Company', auditable_id: Company.where("company_name LIKE 'Test%'").pluck(:id)).destroy_all
```