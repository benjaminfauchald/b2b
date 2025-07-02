# Devise test helpers
module DeviseHelpers
  def sign_in_user(user = nil)
    user ||= create(:user)
    sign_in user
    user
  end
end

RSpec.configure do |config|
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include DeviseHelpers

  # Reset Warden state between tests to prevent authentication pollution
  config.before(:each) do
    if defined?(Warden) && Warden.respond_to?(:test_reset!)
      Warden.test_reset!
    end
  end

  # Additional cleanup for system tests that use authentication
  config.after(:each, type: :system) do
    if defined?(Warden) && Warden.respond_to?(:test_reset!)
      Warden.test_reset!
    end
    # Clear any authentication-related session data
    if defined?(ActionDispatch::Request)
      ActionDispatch::Request.new({}).reset_session rescue nil
    end
  end

  # Additional cleanup for integration tests
  config.after(:each, type: :request) do
    if defined?(Warden) && Warden.respond_to?(:test_reset!)
      Warden.test_reset!
    end
  end
end
