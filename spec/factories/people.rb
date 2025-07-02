FactoryBot.define do
  factory :person do
    sequence(:name) { |n| "Person #{n}" }
    sequence(:profile_url) { |n| "https://linkedin.com/in/person-#{n}" }
    title { "Software Engineer" }
    company_name { "Example Corp" }
    location { "San Francisco, CA" }
    sequence(:email) { |n| "person#{n}@example.com" }
    phone { "+1-555-0100" }
    connection_degree { 1 }
    phantom_run_id { "phantom-run-123" }
    company { nil }
    profile_extracted_at { nil }
    email_extracted_at { nil }
    social_media_extracted_at { nil }
    profile_data { {} }
    email_data { {} }
    social_media_data { {} }

    # Email verification attributes
    email_verification_status { "unverified" }
    email_verification_confidence { 0.0 }
    email_verification_checked_at { nil }
    email_verification_metadata { {} }
  end
end
