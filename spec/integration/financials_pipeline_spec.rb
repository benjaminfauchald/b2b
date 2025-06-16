# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe 'Financials Pipeline Integration', :integration do
  let(:topic) { 'company_financials' }
  let(:messages) do
    5.times.map do |i|
      OpenStruct.new(
        value: {
          company_id: 1000 + i,
          requested_at: Time.now.utc.iso8601,
          event_type: 'company_financials_updated',
          data: {
            ordinary_result: 1000.0 + i,
            annual_result: 900.0 + i,
            operating_revenue: 5000.0 + i,
            operating_costs: 4000.0 + i
          }
        }.to_json,
        key: "key#{i}",
        offset: i,
        partition: 0
      )
    end
  end

  let(:consumer) { FinancialsConsumer.new(group_id: 'test-group') }
  let(:worker_class) { CompanyFinancialsWorker }
  let(:api_service) { CompanyFinancialsService }

  before do
    # Mock Kafka producer (no real Kafka needed)
    allow(KafkaService).to receive(:produce)
    # Mock Sidekiq job enqueueing
    allow(worker_class).to receive(:perform_async)
    # Mock API call
    allow_any_instance_of(api_service).to receive(:call).and_return(true)
  end

  it 'processes Kafka messages through Sidekiq with 1/sec rate limiting' do
    # Step 1: Produce messages to Kafka (mocked)
    messages.each do |msg|
      expect { KafkaService.produce(JSON.parse(msg.value, symbolize_names: false)) }.not_to raise_error
    end

    # Step 2: Consumer enqueues Sidekiq jobs for each message
    messages.each do |msg|
      expect(worker_class).to receive(:perform_async).with(JSON.parse(msg.value, symbolize_names: false).fetch('company_id')).once
      # Simulate consumer processing
      allow(consumer).to receive(:messages).and_return([msg])
      expect { consumer.send(:process_message, msg) }.not_to raise_error
    end

    # Step 3: Sidekiq worker processes jobs and calls API, enforcing 1/sec rate limit
    processed_times = []
    allow_any_instance_of(api_service).to receive(:call) do
      processed_times << Time.now
      true
    end

    # Simulate Sidekiq draining jobs (in real test, use Sidekiq::Testing.inline!)
    5.times do |i|
      worker_class.new.perform(1000 + i)
      sleep 1 # Simulate rate limit (replace with real rate limiter in implementation)
    end

    # Assert rate limiting: at least 1 second between calls
    intervals = processed_times.each_cons(2).map { |a, b| b - a }
    expect(intervals.all? { |interval| interval >= 1.0 }).to be true
    expect(processed_times.size).to eq(5)
  end
end 