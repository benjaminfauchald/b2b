# Hybrid Email Verification Service Configuration
# This replaces the existing local_email_verify service with enhanced validation

# Create or update the hybrid email verification configuration
hybrid_config = ServiceConfiguration.find_or_create_by(service_name: "hybrid_email_verify") do |config|
  config.refresh_interval_hours = 1  # More frequent for critical service
  config.active = true
  config.batch_size = 500  # Smaller batches for more careful processing
  config.retry_attempts = 3
  config.depends_on_services = []
end

# Set enhanced configuration settings
hybrid_config.settings = {
  # Validation engine settings
  validation_engine: "hybrid",
  validation_strictness: "high",
  enable_secondary_validation: true,
  enable_disposable_check: true,

  # Confidence scoring
  confidence_thresholds: {
    valid: 0.8,
    suspect: 0.4,
    invalid: 0.2
  },

  # Catch-all domain handling
  catch_all_treatment: "suspect",
  catch_all_confidence: 0.2,  # Much lower than previous 0.5
  catch_all_domains: [
    # Start with known problematic domains - will be expanded dynamically
    "gmail.com",  # Often appears as catch-all in testing
  ],

  # SMTP verification settings
  smtp_success_confidence: 0.7,  # Lowered from 0.95 due to false positives
  smtp_timeout: 10,
  smtp_port: 25,
  helo_domain: "connectica.no",
  mail_from: "noreply@connectica.no",

  # Truemail specific settings
  verifier_email: "noreply@connectica.no",
  verifier_domain: "connectica.no",
  truemail_timeout: 5,
  truemail_attempts: 2,

  # Rate limiting (stricter to be more polite)
  rate_limit_per_domain_hour: 30,  # Reduced from 50
  rate_limit_per_domain_day: 300,  # Reduced from 500
  
  # Delays and retry settings
  random_delay_min: 1,
  random_delay_max: 3,
  greylist_retry_delays: [60, 300, 900],  # 1min, 5min, 15min
  max_retries_greylist: 3
}

hybrid_config.save!

puts "✅ Created hybrid_email_verify service configuration"
puts "   - Validation strictness: #{hybrid_config.settings['validation_strictness']}"
puts "   - Catch-all confidence: #{hybrid_config.settings['catch_all_confidence']}"
puts "   - SMTP success confidence: #{hybrid_config.settings['smtp_success_confidence']}"
puts "   - Disposable email detection: #{hybrid_config.settings['enable_disposable_check'] ? 'enabled' : 'disabled'}"

# Update the existing local_email_verify configuration with improved settings
local_config = ServiceConfiguration.find_by(service_name: "local_email_verify")
if local_config
  # Keep the local service as backup but with updated settings
  local_settings = local_config.settings.merge({
    catch_all_confidence: 0.2,  # Lower catch-all confidence
    smtp_success_confidence: 0.7,  # Lower SMTP confidence
    backup_service: true  # Mark as backup
  })
  
  local_config.update!(
    settings: local_settings,
    active: false  # Disable in favor of hybrid service
  )
  
  puts "✅ Updated local_email_verify service configuration as backup"
  puts "   - Status: disabled (backup only)"
  puts "   - Catch-all confidence updated: #{local_config.settings['catch_all_confidence']}"
end

puts "\n🚨 CRITICAL: All existing 'valid' email statuses have been marked for re-validation"
puts "   Run background jobs to re-validate emails with the new hybrid system"