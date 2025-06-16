Rails.application.config.service_auditing_enabled = true
Rails.application.config.automatic_auditing_enabled = false

# Configure service auditing settings
Rails.application.configure do
  config.service_auditing = ActiveSupport::OrderedOptions.new

  # Enable/disable service auditing based on environment
  config.service_auditing.enabled = true
  config.service_auditing.automatic = false

  # Configure default settings
  config.service_auditing.default_refresh_interval = 24.hours
  config.service_auditing.default_batch_size = 100
  config.service_auditing.default_retry_attempts = 3

  # Configure cleanup settings
  config.service_auditing.cleanup_after_days = 90
  config.service_auditing.cleanup_batch_size = 1000

  # Configure performance thresholds
  config.service_auditing.performance_thresholds = {
    critical_failure_rate: 0.1,  # 10% failure rate is critical
    warning_failure_rate: 0.05,  # 5% failure rate needs attention
    slow_duration_ms: 5000       # 5 seconds is considered slow
  }
end 