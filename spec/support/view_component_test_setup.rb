# Ensure ViewComponent is properly initialized for tests
require "view_component"
require "view_component/test_helpers"
require "view_component/system_test_helpers"
require "capybara/rspec"

# Configure ViewComponent for test environment
RSpec.configure do |config|
  config.before(:suite) do
    # Ensure components path is loaded
    components_path = Rails.root.join("app/components")
    
    # Add to autoload paths if not already there
    unless Rails.application.config.eager_load_paths.include?(components_path)
      Rails.application.config.eager_load_paths << components_path
    end
    
    # Ensure ViewComponent configuration is loaded
    ViewComponent::Base.config.view_component_path ||= components_path
    ViewComponent::Base.config.test_framework = :rspec
  end

  # Include necessary helpers for component tests
  config.include ViewComponent::TestHelpers, type: :component
  config.include ViewComponent::SystemTestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
  
  # Ensure we have a valid controller context for component tests
  config.before(:each, type: :component) do
    # Set up controller if not already set
    @controller ||= ApplicationController.new
    
    # Set up request context
    if @controller && !@controller.request
      @controller.request = ActionDispatch::TestRequest.create
      @controller.request.env["HTTP_HOST"] = "test.host"
    end
  end
end