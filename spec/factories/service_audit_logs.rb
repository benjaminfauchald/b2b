FactoryBot.define do
  factory :service_audit_log do
    service_name { 'test_service' }
    operation_type { 'process' }
    status { :pending }
    started_at { Time.current }
    association :auditable, factory: :company
    metadata { { 'status' => 'initialized' } }
    columns_affected { [ 'unspecified' ] }
    completed_at { nil }
    execution_time_ms { nil }
    error_message { nil }
    job_id { nil }
    queue_name { nil }
    scheduled_at { nil }
    table_name { 'companies' }
    target_table { nil }
    record_id { auditable&.id || '1' }

    after(:build) do |log|
      # Ensure a valid ServiceConfiguration exists for the service_name, but only if present
      if log.service_name.present?
        ServiceConfiguration.find_or_create_by!(service_name: log.service_name) do |config|
          config.refresh_interval_hours = 24
          config.active = true
          config.batch_size = 100
          config.retry_attempts = 3
          config.settings = {}
        end
      end
      log.table_name ||= log.auditable&.class&.table_name || 'companies'
      log.record_id ||= log.auditable&.id&.to_s || '1'
    end

    trait :success do
      status { :success }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      completed_at { Time.current }
      error_message { 'Some error' }
      metadata { { 'error' => 'Some error occurred' } }
    end

    trait :with_metadata do
      metadata do
        {
          'company_id' => auditable&.id,
          'registration_number' => auditable&.registration_number
        }
      end
    end

    trait :with_columns do
      columns_affected { [ 'company_name', 'email' ] }
    end

    trait :with_job_info do
      job_id { SecureRandom.uuid }
      queue_name { 'default' }
      scheduled_at { 5.minutes.ago }
    end

    trait :for_domain do
      association :auditable, factory: :domain
      service_name { 'domain_enhancement' }
      table_name { 'domains' }
    end

    trait :for_company do
      association :auditable, factory: :company
      service_name { 'company_enhancement' }
      table_name { 'companies' }
    end

    trait :long_running do
      started_at { 30.seconds.ago }
      completed_at { 1.second.ago }
      execution_time_ms { 29000 }
    end

    trait :recent do
      created_at { 1.hour.ago }
    end

    trait :old do
      created_at { 1.week.ago }
    end
  end
end
