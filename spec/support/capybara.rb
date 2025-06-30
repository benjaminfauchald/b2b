# Capybara configuration for component tests
require 'capybara/rspec'

RSpec.configure do |config|
  # Use rack_test driver for component tests (faster than selenium)
  config.before(:each, type: :component) do
    Capybara.current_driver = :rack_test
  end

  # Configure Capybara for CI environments
  if ENV['CI']
    Capybara.register_driver :selenium_chrome_headless do |app|
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-gpu')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--window-size=1400,1400')

      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end

    Capybara.javascript_driver = :selenium_chrome_headless
  end

  # Default settings
  Capybara.default_max_wait_time = 5
  Capybara.server = :puma, { Silent: true }
end
