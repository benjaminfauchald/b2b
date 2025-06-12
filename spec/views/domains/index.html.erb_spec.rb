require 'rails_helper'

RSpec.describe "domains/index", type: :view do
  before(:each) do
    assign(:domains, [
      Domain.create!(
        domain: "Domain Name",
        www: false,
        mx: false
      ),
      Domain.create!(
        domain: "Domain Name",
        www: false,
        mx: false
      )
    ])
  end

  it "renders a list of domains" do
    render
    cell_selector = Rails::VERSION::STRING >= '7' ? 'div>p' : 'tr>td'
    assert_select cell_selector, text: Regexp.new("Domain Name".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(false.to_s), count: 4
    assert_select cell_selector, text: Regexp.new(false.to_s), count: 4
  end
end
