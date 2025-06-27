# Company Enhancement Services Configuration Seeds

puts "Creating Company Enhancement Service Configurations..."

# Financial Data Service
ServiceConfiguration.find_or_create_by(service_name: 'company_financial_data') do |config|
  config.active = true
  config.refresh_interval_hours = 720  # 30 days
  config.batch_size = 100
  config.retry_attempts = 3
  config.settings = {
    api_endpoint: ENV['BRREG_API_ENDPOINT'],
    rate_limit: 100,
    timeout: 30
  }
end

# Web Discovery Service
ServiceConfiguration.find_or_create_by(service_name: 'company_web_discovery') do |config|
  config.active = true
  config.refresh_interval_hours = 2160  # 90 days
  config.batch_size = 50
  config.retry_attempts = 3
  config.settings = {
    search_engines: [ 'google', 'bing' ],
    rate_limit: 50,
    timeout: 45,
    max_results_per_engine: 10
  }
end

# LinkedIn Discovery Service
ServiceConfiguration.find_or_create_by(service_name: 'company_linkedin_discovery') do |config|
  config.active = true
  config.refresh_interval_hours = 1440  # 60 days
  config.batch_size = 30
  config.retry_attempts = 3
  config.settings = {
    api_endpoint: ENV['LINKEDIN_API_ENDPOINT'],
    rate_limit: 30,
    timeout: 30,
    confidence_threshold: 0.7
  }
end

# Employee Discovery Service
ServiceConfiguration.find_or_create_by(service_name: 'company_employee_discovery') do |config|
  config.active = true
  config.refresh_interval_hours = 1080  # 45 days
  config.batch_size = 20
  config.retry_attempts = 3
  config.settings = {
    sources: [ 'linkedin', 'company_websites', 'public_registries' ],
    rate_limit: 20,
    timeout: 60,
    max_employees_to_discover: 100
  }
end

puts "✓ Company Enhancement Service Configurations created successfully"
