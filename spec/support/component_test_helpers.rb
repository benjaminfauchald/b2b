# Component test helpers
module ComponentTestHelpers
  def render_component(component)
    render_inline(component)
  end

  # Mock helper methods that components might need
  def number_with_delimiter(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def form_authenticity_token
    "test-token"
  end

  def hidden_field_tag(name, value)
    "<input type='hidden' name='#{name}' value='#{value}' />".html_safe
  end

  # Add path helpers for components that need them
  def queue_single_web_content_domain_path(domain)
    "/domains/#{domain.id}/queue_single_web_content"
  end

  def queue_single_dns_domain_path(domain)
    "/domains/#{domain.id}/queue_single_dns"
  end

  def queue_single_mx_domain_path(domain)
    "/domains/#{domain.id}/queue_single_mx"
  end

  def queue_single_www_domain_path(domain)
    "/domains/#{domain.id}/queue_single_www"
  end
end

RSpec.configure do |config|
  config.include ComponentTestHelpers, type: :component
  config.include ActionView::Helpers::FormTagHelper, type: :component

  # Mock Company model methods for tests
  config.before(:each, type: :component) do
    allow(Company).to receive(:needs_financial_update).and_return(double(count: 0))
    allow(Company).to receive(:web_discovery_potential).and_return(double(count: 0))
    allow(Company).to receive(:linkedin_discovery_potential).and_return(double(count: 0))
  end
end
