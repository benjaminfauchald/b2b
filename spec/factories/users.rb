FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'Password123!' }
    name { 'Example User' }
    # Add other required fields as needed
  end
end
