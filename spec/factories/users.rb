FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    password_confirmation { "password123" }

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

    # OAuth-specific traits
    trait :oauth_user do
      provider { [ 'google_oauth2', 'github' ].sample }
      sequence(:uid) { |n| "oauth_uid_#{n}" }
      password { nil }
      password_confirmation { nil }
    end

    trait :google_oauth do
      provider { 'google_oauth2' }
      sequence(:uid) { |n| "google_#{n}" }
      sequence(:email) { |n| "user#{n}@gmail.com" }
      password { nil }
      password_confirmation { nil }
    end

    trait :github_oauth do
      provider { 'github' }
      sequence(:uid) { |n| "github_#{n}" }
      sequence(:email) { |n| "user#{n}@users.noreply.github.com" }
      password { nil }
      password_confirmation { nil }
    end
  end
end
