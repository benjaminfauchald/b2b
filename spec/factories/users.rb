FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'Password123!' }
    name { 'Example User' }
    # Add other required fields as needed

    trait :without_email do
      email { nil }
    end

    trait :without_name do
      name { nil }
    end

    trait :with_yahoo_email do
      sequence(:email) { |n| "user#{n}@yahoo.com" }
    end

    trait :with_gmail_email do
      sequence(:email) { |n| "user#{n}@gmail.com" }
    end

    trait :with_outlook_email do
      sequence(:email) { |n| "user#{n}@outlook.com" }
    end

    trait :with_icloud_email do
      sequence(:email) { |n| "user#{n}@icloud.com" }
    end
  end
end
