FactoryBot.define do
  factory :domain do
    domain { "example#{rand(1000)}.com" }
    www { false }
    mx { false }
    dns { nil }  # Default state for new domains
  end
end
