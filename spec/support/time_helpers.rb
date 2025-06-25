# Helpers for freezing time in tests
module TimeHelpers
  def freeze_time(&block)
    travel_to(Time.current, &block)
  end
end

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
  config.include TimeHelpers
end
