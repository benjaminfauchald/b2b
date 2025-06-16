require 'rails_helper'

RSpec.describe "domains/new", type: :view do
  before(:each) do
    assign(:domain, Domain.new(
      domain: "MyString",
      www: false,
      mx: false
    ))
  end

  it "renders new domain form" do
    render

    assert_select "form[action=?][method=?]", domains_path, "post" do

      assert_select "input[name=?]", "domain[domain]"

      assert_select "input[name=?]", "domain[www]"

      assert_select "input[name=?]", "domain[mx]"

      assert_select "input[name=?]", "domain[dns]"
    end
  end
end
