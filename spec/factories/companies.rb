# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    sequence(:company_name) { |n| "Company #{n}" }
    sequence(:registration_number) { |n| "REG#{n}" }
    source_country { 'NO' }
    source_registry { 'brreg' }
    source_id { registration_number }
    organization_form_code { 'AS' }
    organization_form_description { 'Aksjeselskap' }
    primary_industry_code { Faker::Number.number(digits: 5).to_s }
    primary_industry_description { Faker::Company.industry }
    website { Faker::Internet.url }
    email { Faker::Internet.email }
    phone { Faker::PhoneNumber.phone_number }
    postal_address { Faker::Address.street_address }
    postal_code { Faker::Address.postcode }
    postal_city { Faker::Address.city }
    postal_country { 'Norway' }
    postal_country_code { 'NO' }
    has_registered_employees { true }
    employee_count { Faker::Number.between(from: 1, to: 1000) }
    employee_registration_date_registry { Faker::Date.between(from: 5.years.ago, to: Date.today) }
    employee_registration_date_nav { Faker::Date.between(from: 5.years.ago, to: Date.today) }

    # Financial fields
    ordinary_result { Faker::Number.between(from: -1_000_000, to: 1_000_000) }
    annual_result { Faker::Number.between(from: -1_000_000, to: 1_000_000) }
    operating_revenue { Faker::Number.between(from: 0, to: 10_000_000) }
    operating_costs { Faker::Number.between(from: 0, to: 9_000_000) }
    http_error { nil }
    http_error_message { nil }

    trait :with_financial_data do
    end

    trait :with_failed_financial_data do
      http_error { 500 }
      http_error_message { 'Internal Server Error' }
    end

    trait :with_stale_financial_data do
    end
  end
end
