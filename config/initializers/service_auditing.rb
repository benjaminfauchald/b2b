Rails.application.configure do
  config.service_auditing_enabled = !Rails.env.test?
  config.service_auditing = ActiveSupport::OrderedOptions.new
  config.service_auditing.cleanup_after_days = 90
  config.service_auditing.default_batch_size = 1000
  config.service_auditing.default_retry_attempts = 3
  config.service_auditing.performance_monitoring = true
end 