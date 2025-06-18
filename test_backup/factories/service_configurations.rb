FactoryBot.define do
  factory :service_configuration do
    sequence(:service_name) { |n| "test_service_#{n}" }
    refresh_interval_hours { 720 }
    depends_on_services { [] }
    active { true }
    batch_size { 1000 }
    retry_attempts { 3 }
    settings { {} }

    trait :inactive do
      active { false }
    end

    trait :frequent_refresh do
      refresh_interval_hours { 24 }
    end

    trait :infrequent_refresh do
      refresh_interval_hours { 2160 } # 90 days
    end

    trait :with_dependencies do
      depends_on_services { [ 'user_enhancement', 'domain_testing' ] }
    end

    trait :with_settings do
      settings do
        {
          'timeout_seconds' => 30,
          'max_retries' => 5,
          'enable_logging' => true
        }
      end
    end

    trait :large_batch do
      batch_size { 5000 }
    end

    trait :small_batch do
      batch_size { 100 }
    end

    trait :no_retries do
      retry_attempts { 0 }
    end

    trait :high_retries do
      retry_attempts { 10 }
    end

    trait :user do
      service_name { generate(:service_name) }
      refresh_interval_hours { 168 } # 1 week
      settings do
        {
          'fields_to_enhance' => [ 'email', 'profile' ],
          'validation_enabled' => true
        }
      end
    end

    trait :domain do
      service_name { generate(:service_name) }
      refresh_interval_hours { 24 } # daily
      depends_on_services { [ 'dns_resolution' ] }
      settings do
        {
          'timeout_seconds' => 5,
          'test_types' => [ 'A', 'MX', 'NS' ]
        }
      end
    end
  end
end
