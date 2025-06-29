# Integration test helpers
module IntegrationHelpers
  def controller
    @controller ||= ApplicationController.new
  end

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until finished_all_ajax_requests?
    end
  end

  def finished_all_ajax_requests?
    page.evaluate_script('jQuery.active').zero?
  rescue Capybara::NotSupportedByDriverError
    true
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, type: :feature
  config.include IntegrationHelpers, type: :system
  config.include IntegrationHelpers, type: :request
end
