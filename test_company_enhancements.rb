#!/usr/bin/env ruby
# Test script for Company Enhancement Services

puts "🧪 Testing Company Enhancement Services"
puts "=" * 50

# 1. Create a test company
puts "\n1️⃣ Creating test company..."
company = Company.create!(
  registration_number: "999888777",
  company_name: "Test Enhancement Company AS",
  organization_form_code: "AS",
  organization_form_description: "Aksjeselskap",
  primary_industry_code: "62010",
  primary_industry_description: "Computer programming activities",
  employee_count: 50,
  website: "https://testcompany.no",
  email: "test@testcompany.no",
  postal_address: "Testveien 123",
  postal_city: "Oslo",
  postal_code: "0123",
  postal_country: "Norway"
)
puts "✅ Created company: #{company.company_name} (ID: #{company.id})"

# 2. Check service configurations
puts "\n2️⃣ Checking service configurations..."
services = ['company_financial_data', 'company_web_discovery', 'company_linkedin_discovery', 'company_employee_discovery']
services.each do |service_name|
  config = ServiceConfiguration.find_by(service_name: service_name)
  if config
    puts "✅ #{service_name}: #{config.active? ? 'ACTIVE' : 'INACTIVE'}"
  else
    puts "❌ #{service_name}: NOT CONFIGURED"
  end
end

# 3. Test Financial Data Service
puts "\n3️⃣ Testing Financial Data Service..."
financial_service = CompanyFinancialDataService.new(company)
result = financial_service.perform
if result.success?
  puts "✅ Financial data service: #{result.message}"
  puts "   Revenue: #{company.reload.revenue}"
  puts "   Profit: #{company.profit}"
else
  puts "❌ Financial data service failed: #{result.error}"
end

# 4. Test Web Discovery Service
puts "\n4️⃣ Testing Web Discovery Service..."
web_service = CompanyWebDiscoveryService.new(company)
result = web_service.perform
if result.success?
  puts "✅ Web discovery service: #{result.message}"
  puts "   Web pages found: #{company.reload.web_pages&.count || 0}"
else
  puts "❌ Web discovery service failed: #{result.error}"
end

# 5. Test LinkedIn Discovery Service
puts "\n5️⃣ Testing LinkedIn Discovery Service..."
linkedin_service = CompanyLinkedinDiscoveryService.new(company)
result = linkedin_service.perform
if result.success?
  puts "✅ LinkedIn discovery service: #{result.message}"
  puts "   LinkedIn URL: #{company.reload.linkedin_url || 'Not found'}"
else
  puts "❌ LinkedIn discovery service failed: #{result.error}"
end

# 6. Test Employee Discovery Service
puts "\n6️⃣ Testing Employee Discovery Service..."
employee_service = CompanyEmployeeDiscoveryService.new(company)
result = employee_service.perform
if result.success?
  puts "✅ Employee discovery service: #{result.message}"
  puts "   Employees found: #{company.reload.employees_data&.count || 0}"
else
  puts "❌ Employee discovery service failed: #{result.error}"
end

# 7. Check Service Audit Logs
puts "\n7️⃣ Checking Service Audit Logs..."
audit_logs = ServiceAuditLog.where(auditable: company).order(created_at: :desc)
puts "Found #{audit_logs.count} audit logs:"
audit_logs.each do |log|
  puts "   - #{log.service_name}: #{log.status} (#{log.execution_time_ms}ms)"
end

# 8. Test Background Workers
puts "\n8️⃣ Testing Background Workers..."
services.each do |service_name|
  worker_class = "#{service_name.camelize}Worker".constantize
  worker_class.perform_async(company.id)
  puts "✅ Queued #{worker_class.name}"
end

# 9. Check Queue Status
puts "\n9️⃣ Checking Queue Status..."
require 'sidekiq/api'
services.each do |service_name|
  queue = Sidekiq::Queue.new(service_name)
  puts "   #{service_name}: #{queue.size} jobs queued"
end

puts "\n✨ Testing complete!"
puts "=" * 50