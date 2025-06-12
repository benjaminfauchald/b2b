FactoryBot.define do
  factory :service_audit_log do
    association :auditable, factory: :user
    service_name { 'test_service_v1' }
    action { 'process' }
    status { :pending }
    context { {} }
    changed_fields { [] }

    trait :success do
      status { :success }
      started_at { 2.seconds.ago }
      completed_at { 1.second.ago }
      duration_ms { 1000 }
    end

    trait :failed do
      status { :failed }
      started_at { 2.seconds.ago }
      completed_at { 1.second.ago }
      duration_ms { 1500 }
      error_message { 'Test error message' }
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
      service_name { 'domain_enhancement_v1' }
    end

    trait :for_user do
      association :auditable, factory: :user
      service_name { 'user_enhancement_v1' }
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