# ViewComponent test helpers
module ViewComponentHelpers
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers::FormHelper
  include ActionView::Helpers::FormTagHelper
  
  def with_controller_class(klass)
    old_controller = @controller
    @controller = klass.new
    yield
  ensure
    @controller = old_controller
  end

  def with_request_url(url)
    old_url = request.url
    request.env['REQUEST_URI'] = url
    yield
  ensure
    request.env['REQUEST_URI'] = old_url
  end
end

RSpec.configure do |config|
  config.include ViewComponentHelpers, type: :component
  
  config.before(:each, type: :component) do
    # Set up a default controller for component tests
    @controller = ApplicationController.new
  end
end