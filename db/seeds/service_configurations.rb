# Service Configuration Seeds
# This file ensures all services have proper SCT entries

puts "🌱 Seeding Service Configurations..."

# Person Email Extraction Service (Hunter.io)
ServiceConfiguration.find_or_create_by(service_name: "person_email_extraction") do |config|
  config.active = true
  config.refresh_interval_hours = 168  # 7 days
  config.batch_size = 50              # Hunter.io rate limits
  config.retry_attempts = 3
  config.depends_on_services = []
  config.settings = {
    "api_provider" => "hunter_io",
    "rate_limit_per_second" => 15,
    "rate_limit_per_minute" => 500,
    "timeout_seconds" => 30,
    "requires_company_website" => true,
    "requires_person_name" => true
  }
end

puts "✅ Person Email Extraction service configuration created/updated"

# Add other service configurations here as needed...

puts "🎉 Service configuration seeding completed!"
