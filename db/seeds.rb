# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Service Audit System Configuration Seeds
puts "Setting up Service Audit System configurations..."

# User Enhancement Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'user_enhancement') do |config|
  config.refresh_interval_hours = 720  # 30 days
  config.batch_size = 1000
  config.retry_attempts = 3
  config.active = true
  config.depends_on_services = []
  config.settings = {
    enhance_email: true,
    enhance_name: true,
    classify_providers: true
  }
end

# Domain DNS Testing Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'domain_testing') do |config|
  config.refresh_interval_hours = 168  # 7 days
  config.batch_size = 500
  config.retry_attempts = 2
  config.active = true
  config.depends_on_services = []
  config.settings = {
    dns_timeout_seconds: 5,
    treat_timeout_as_failure: true,
    retry_network_errors: true,
    log_dns_details: true
  }
end

# Domain A Record Testing Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'domain_a_record_testing') do |config|
  config.refresh_interval_hours = 168  # 7 days
  config.batch_size = 500
  config.retry_attempts = 2
  config.active = true
  config.depends_on_services = [ 'domain_testing' ]  # Depends on DNS testing
  config.settings = {
    www_timeout_seconds: 5,
    treat_timeout_as_failure: true,
    retry_network_errors: true,
    log_www_details: true
  }
end

# Company Financial Data Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'company_financial_data') do |config|
  config.refresh_interval_hours = 720  # 30 days
  config.batch_size = 100
  config.retry_attempts = 3
  config.active = true
  config.depends_on_services = []
  config.settings = {
    api_timeout_seconds: 10,
    rate_limit_delay_seconds: 1,
    cache_responses: true
  }
end

# Company Web Discovery Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'company_web_discovery') do |config|
  config.refresh_interval_hours = 1440  # 60 days
  config.batch_size = 50
  config.retry_attempts = 2
  config.active = true
  config.depends_on_services = []
  config.settings = {
    search_timeout_seconds: 30,
    max_results_per_search: 10,
    verify_ssl_certificates: true
  }
end

# Company LinkedIn Discovery Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'company_linkedin_discovery') do |config|
  config.refresh_interval_hours = 1440  # 60 days
  config.batch_size = 50
  config.retry_attempts = 2
  config.active = true
  config.depends_on_services = []
  config.settings = {
    search_timeout_seconds: 30,
    use_company_name_variations: true,
    confidence_threshold: 0.7
  }
end

# Company Employee Discovery Service Configuration
ServiceConfiguration.find_or_create_by(service_name: 'company_employee_discovery') do |config|
  config.refresh_interval_hours = 2160  # 90 days
  config.batch_size = 25
  config.retry_attempts = 2
  config.active = true
  config.depends_on_services = ['company_linkedin_discovery']
  config.settings = {
    search_timeout_seconds: 45,
    max_employees_per_company: 50,
    include_former_employees: false
  }
end

# Automatic Audit Configuration
ServiceConfiguration.find_or_create_by(service_name: 'automatic_audit') do |config|
  config.refresh_interval_hours = 0  # No refresh needed for automatic audits
  config.batch_size = 1
  config.retry_attempts = 1
  config.active = true
  config.depends_on_services = []
  config.settings = {
    audit_creates: true,
    audit_updates: true,
    audit_destroys: false
  }
end

puts "Service Audit System configured successfully!"
puts "Available services:"
ServiceConfiguration.all.each do |config|
  status = config.active? ? "ACTIVE" : "INACTIVE"
  puts "  - #{config.service_name} [#{status}]"
end
