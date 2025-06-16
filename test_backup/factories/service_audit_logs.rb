FactoryBot.define do
  factory :service_audit_log do
    association :auditable, factory: :user
    service_name { 'test_audit' }
    action { 'process' }
    status { :pending }
    context { {} }
    changed_fields { [] }
    started_at { Time.current }
    completed_at { nil }
    duration_ms { nil }
    error_message { nil }
    job_id { nil }
    queue_name { nil }
    scheduled_at { nil }

    after(:build) do |log|
      # Ensure a valid ServiceConfiguration exists for the service_name
      ServiceConfiguration.find_or_create_by!(service_name: log.service_name) do |config|
        config.refresh_interval_hours = 24
        config.active = true
        config.batch_size = 100
        config.retry_attempts = 3
        config.settings = {}
      end
    end

    trait :success do
      status { :success }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      completed_at { Time.current }
      error_message { 'Some error' }
    end

    trait :with_context do
      context do
        {
          'user_id' => auditable&.id,
          'ip_address' => '127.0.0.1',
          'user_agent' => 'Test Agent'
        }
      end
    end

    trait :with_changes do
      changed_fields { ['name', 'email'] }
    end

    trait :with_job_info do
      job_id { SecureRandom.uuid }
      queue_name { 'default' }
      scheduled_at { 5.minutes.ago }
    end

    trait :for_domain do
      association :auditable, factory: :domain
      service_name { 'domain_enhancement' }
    end

    trait :for_user do
      association :auditable, factory: :user
      service_name { 'user_enhancement' }
    end

    trait :long_running do
      started_at { 30.seconds.ago }
      completed_at { 1.second.ago }
      duration_ms { 29000 }
    end

    trait :recent do
      created_at { 1.hour.ago }
    end

    trait :old do
      created_at { 1.week.ago }
    end
  end
end 