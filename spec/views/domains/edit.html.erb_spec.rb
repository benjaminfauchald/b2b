require 'rails_helper'

RSpec.describe "domains/edit", type: :view do
  let(:domain) {
    Domain.create!(
      domain: "MyString",
      www: false,
      mx: false
    )
  }

  before(:each) do
    assign(:domain, domain)
  end

  it "renders the edit domain form" do
    render

    assert_select "form[action=?][method=?]", domain_path(domain), "post" do

      assert_select "input[name=?]", "domain[domain]"

      assert_select "input[name=?]", "domain[www]"

      assert_select "input[name=?]", "domain[mx]"

      assert_select "input[name=?]", "domain[dns]"
    end
  end
end
