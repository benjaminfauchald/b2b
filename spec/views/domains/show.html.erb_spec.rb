require 'rails_helper'

RSpec.describe "domains/show", type: :view do
  before(:each) do
    assign(:domain, Domain.create!(
      domain: "Domain Name",
      www: false,
      mx: false
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Domain Name/)
    expect(rendered).to match(/false/)
    expect(rendered).to match(/false/)
  end
end
