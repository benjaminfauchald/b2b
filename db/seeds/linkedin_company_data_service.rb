# frozen_string_literal: true

# LinkedIn Company Data Service Configuration
# Creates the necessary ServiceConfiguration record for the LinkedIn Company Data Service

puts "Setting up LinkedIn Company Data Service configuration..."

# Create or update service configuration
config = ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_data") do |c|
  c.active = true
  c.configuration_data = {
    rate_limit_per_hour: 100,
    timeout_seconds: 30,
    retry_attempts: 3,
    cache_duration_hours: 24,
    batch_size: 10,
    authentication_method: "username_password", # or "cookie"
    supported_identifiers: ["numeric_id", "slug", "url"]
  }
  c.description = "LinkedIn Company Data Extraction Service - Extracts company information from LinkedIn using company IDs, slugs, or URLs"
end

if config.persisted?
  puts "✓ LinkedIn Company Data Service configuration created"
  puts "  Service Name: #{config.service_name}"
  puts "  Active: #{config.active?}"
  puts "  Configuration: #{config.configuration_data}"
else
  puts "✗ Failed to create LinkedIn Company Data Service configuration"
  puts "  Errors: #{config.errors.full_messages.join(', ')}"
end

# Create sample audit log entry for testing
sample_audit = ServiceAuditLog.create!(
  service_name: "linkedin_company_data",
  operation_type: "extract",
  status: :success,
  table_name: "companies",
  record_id: "sample",
  columns_affected: ["none"],
  metadata: {
    company_id: "1035",
    company_name: "Microsoft",
    universal_name: "microsoft",
    identifier_type: "slug",
    data_freshness: "fresh",
    test_entry: true
  },
  started_at: Time.current,
  completed_at: Time.current,
  execution_time_ms: 1500
)

puts "✓ Sample audit log entry created for testing"

puts "\nLinkedIn Company Data Service setup complete!"
puts "\nNext steps:"
puts "1. Set environment variables:"
puts "   export LINKEDIN_EMAIL='your_email@example.com'"
puts "   export LINKEDIN_PASSWORD='your_password'"
puts "   # OR use cookie authentication:"
puts "   export LINKEDIN_COOKIE_LI_AT='your_li_at_cookie'"
puts "2. Install Python dependencies:"
puts "   rake linkedin_company_data:install_deps"
puts "3. Test the service:"
puts "   rake linkedin_company_data:test"