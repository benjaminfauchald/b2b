FactoryBot.define do
  factory :domain do
    sequence(:domain) { |n| "domain#{n}.com" }
    www { false }
    mx { false }
    dns { nil }  # Default state for new domains
    a_record_ip { nil }
    web_content_data { nil }
    
    trait :with_dns do
      dns { true }
    end
    
    trait :with_mx do
      dns { true }
      mx { true }
    end
    
    trait :with_www do
      dns { true }
      www { true }
      a_record_ip { "192.168.1.1" }
    end
    
    trait :with_web_content do
      dns { true }
      www { true }
      a_record_ip { "192.168.1.1" }
      web_content_data { { title: "Test Site", content: "Test content" } }
    end
  end
end
