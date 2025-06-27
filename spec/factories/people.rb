FactoryBot.define do
  factory :person do
    name { "MyString" }
    profile_url { "MyString" }
    title { "MyString" }
    company_name { "MyString" }
    location { "MyString" }
    email { "MyString" }
    phone { "MyString" }
    connection_degree { 1 }
    phantom_run_id { "MyString" }
    company { nil }
    profile_extracted_at { "2025-06-26 01:17:14" }
    email_extracted_at { "2025-06-26 01:17:14" }
    social_media_extracted_at { "2025-06-26 01:17:14" }
    profile_data { "" }
    email_data { "" }
    social_media_data { "" }
  end
end
