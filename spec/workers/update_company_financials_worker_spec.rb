# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompanyFinancialsWorker do
  let(:worker) { described_class.new }
  let(:companies) { [] }

  before do
    # Create service configuration for the test
    create(:service_configuration, service_name: 'company_financials', active: true)

    # Create test companies
    3.times do |i|
      company = create(:company, registration_number: "TEST#{1000 + i}")
      companies << company
    end

    # Mock SCT logging in worker
    allow_any_instance_of(described_class).to receive(:log_to_sct)

    # Mock ServiceAuditLog creation
    audit_log_double = double('ServiceAuditLog',
      mark_success!: true,
      mark_failed!: true,
      add_metadata: true,
      update!: true,
      started_at: Time.current
    )
    allow(ServiceAuditLog).to receive(:create!).and_return(audit_log_double)

    # Clear Redis rate limiting keys before each test
    begin
      Sidekiq.redis do |redis|
        redis.del("company_financials_service:global_api_lock")
        redis.del("company_financials_service:last_api_call")
      end
    rescue => e
      Rails.logger.warn "Could not clear Redis keys in test: #{e.message}"
    end
  end

  it 'enforces a minimum 1 second delay between API calls' do
    processed_times = []

    # Mock needs_update? to return true so the service will make API calls
    allow_any_instance_of(CompanyFinancialsService).to receive(:needs_update?).and_return(true)

    # Mock the make_api_request method to capture timing and avoid actual API calls
    original_make_api_request = CompanyFinancialsService.instance_method(:make_api_request)
    allow_any_instance_of(CompanyFinancialsService).to receive(:make_api_request) do |service_instance|
      # Call the actual enforce_rate_limit! method before capturing timing
      service_instance.send(:enforce_rate_limit!)
      processed_times << Time.now
      # Return mock financial data
      {
        parsed_data: {
          ordinary_result: 1000,
          annual_result: 900,
          operating_revenue: 5000,
          operating_costs: 4000
        },
        raw_response: '{"mock": "data"}'
      }
    end

    # Process 3 jobs in quick succession
    start_time = Time.now
    companies.each do |company|
      worker.perform(company.id)
    end
    end_time = Time.now

    # Assert that the API was called 3 times
    expect(processed_times.size).to eq(3)

    # Assert rate limiting: at least 1 second between calls (allowing small margin for test timing)
    intervals = processed_times.each_cons(2).map { |a, b| b - a }
    total_time = end_time - start_time
    puts "DEBUG: Processed times: #{processed_times.map(&:to_f)}"
    puts "DEBUG: Intervals: #{intervals}"
    puts "DEBUG: Total time: #{total_time}"
    expect(intervals.all? { |interval| interval >= 0.9 }).to be true

    # Assert total time is at least 2 seconds (for 3 calls with 1 second between each)
    expect(total_time).to be >= 1.8 # Allow small margin for test timing
  end
end
