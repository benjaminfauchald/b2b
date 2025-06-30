# ViewComponent test setup
# Ensure ViewComponent is properly initialized before tests run

# Make sure ViewComponent is loaded
require 'view_component'
require 'view_component/test_helpers'
require 'view_component/system_test_helpers'

# Configure ViewComponent for tests
ViewComponent::Base.config.view_component_path = Rails.root.join("app/components").to_s
ViewComponent::Base.config.test_framework = :rspec

# Ensure component templates can be found
ViewComponent::Base.config.view_paths = [Rails.root.join("app/views").to_s]

# Set up test controller for rendering components
class ViewComponentTestController < ActionController::Base
  include Rails.application.routes.url_helpers
end

RSpec.configure do |config|
  config.before(:each, type: :component) do
    # Ensure we have a controller context for rendering
    @controller = ViewComponentTestController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @controller.request = @request
    @controller.response = ActionDispatch::TestResponse.new
  end
end