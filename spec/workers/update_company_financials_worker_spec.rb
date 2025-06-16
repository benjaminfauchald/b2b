# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompanyFinancialsWorker do
  let(:worker) { described_class.new }
  let(:api_service) { CompanyFinancialsService }

  it 'enforces a minimum 1 second delay between API calls' do
    processed_times = []
    allow_any_instance_of(api_service).to receive(:call) do |instance|
      processed_times << Time.now
      true
    end

    # Simulate processing 3 jobs in quick succession
    3.times do |i|
      worker.perform(1000 + i)
      sleep 1
    end

    # Assert at least 1 second between each call
    intervals = processed_times.each_cons(2).map { |a, b| b - a }
    expect(intervals.all? { |interval| interval >= 1.0 }).to be true
    expect(processed_times.size).to eq(3)
  end
end 