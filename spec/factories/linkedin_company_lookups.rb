FactoryBot.define do
  factory :linkedin_company_lookup do
    linkedin_company_id { Faker::Number.unique.number(digits: 8).to_s }
    association :company
    linkedin_slug { Faker::Internet.slug }
    confidence_score { 95 }
    last_verified_at { 1.day.ago }
  end
end