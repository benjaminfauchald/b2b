require 'rails_helper'

RSpec.describe User, type: :model do
  it "is valid with valid attributes" do
    user = User.new(name: "Example", email: "user@example.com")
    expect(user).to be_valid
  end
end