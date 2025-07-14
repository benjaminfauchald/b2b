# LinkedIn Company Association Service Configurations

# Main association service - runs every 2 hours
ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_association") do |config|
  config.active = true
  config.refresh_interval_hours = 2
  config.batch_size = 500
  config.retry_attempts = 3
  config.settings = {
    "max_processing_time_minutes" => 30,
    "enable_immediate_processing" => true,
    "priority_new_imports" => true,
    "confidence_threshold" => 75,
    "enable_fallback_matching" => false,
    "cache_duration_hours" => 1,
    "max_daily_api_calls" => 100,
    "max_api_calls_per_run" => 50
  }
end

# Slug population service - runs every 12 hours
ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_slug_population") do |config|
  config.active = true
  config.refresh_interval_hours = 12
  config.batch_size = 100
  config.retry_attempts = 2
  config.settings = {
    "force_refresh_threshold_days" => 7,
    "validate_existing_slugs" => true,
    "cleanup_stale_entries" => true,
    "update_lookup_table" => true
  }
end

# LinkedIn ID population service - runs every 24 hours (converts slugs to IDs)
ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_id_population") do |config|
  config.active = true
  config.refresh_interval_hours = 24
  config.batch_size = 50
  config.retry_attempts = 3
  config.settings = {
    "api_rate_limit_per_hour" => 100,
    "update_lookup_table" => true,
    "skip_recently_updated" => true
  }
end

puts "LinkedIn Company Association service configurations created/updated"