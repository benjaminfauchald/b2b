FactoryBot.define do
  factory :domain do
    sequence(:domain) { |n| "domain#{n}.com" }
    www { false }
    mx { false }
    dns { nil }  # Default state for new domains
  end
end
