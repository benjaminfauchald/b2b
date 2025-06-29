# Helper module for request specs that need authentication
module DeviseRequestHelpers
  def login_user(user = nil)
    user ||= create(:user)

    # For request specs, we need to actually go through the login process
    # or use Warden test helpers
    login_as(user, scope: :user)
    user
  end

  def login_admin
    admin = create(:user, email: 'admin@example.com')
    login_as(admin, scope: :user)
    admin
  end
end

# Configure RSpec
RSpec.configure do |config|
  # Include Rails route helpers
  config.include Rails.application.routes.url_helpers

  # Include Devise helpers for different spec types
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Warden::Test::Helpers, type: :request
  config.include Warden::Test::Helpers, type: :system
  config.include DeviseRequestHelpers, type: :request

  # Reset Warden after each test
  config.after(type: :request) do
    Warden.test_reset!
  end

  # Ensure Devise mappings and routes are loaded
  config.before(:suite) do
    # Load all devise mappings and routes
    Rails.application.reload_routes!
  end

  # Ensure routes are available in each test
  config.before(:each, type: :request) do
    # Make sure routes are loaded
    Rails.application.reload_routes! if Rails.application.routes.routes.empty?
  end
end
