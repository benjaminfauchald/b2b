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
  config.include DeviseHelpers
end
