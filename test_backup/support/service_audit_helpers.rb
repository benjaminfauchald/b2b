module ServiceAuditHelpers
  def disable_automatic_auditing
    allow(Rails.application.config).to receive(:service_auditing_enabled).and_return(false)
  end

  def enable_automatic_auditing
    allow(Rails.application.config).to receive(:service_auditing_enabled).and_return(true)
  end

  def with_auditing_disabled
    original = Rails.application.config.service_auditing_enabled
    disable_automatic_auditing
    yield
  ensure
    allow(Rails.application.config).to receive(:service_auditing_enabled).and_return(original)
  end
end

RSpec.configure do |config|
  config.include ServiceAuditHelpers
end
