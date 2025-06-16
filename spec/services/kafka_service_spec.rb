# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KafkaService do
  let(:valid_message) { { company_id: 12345, requested_at: '2025-06-16T12:00:00Z' } }
  let(:invalid_message) { { company_id: 'not-an-integer' } }

  describe '.produce' do
    it 'accepts a valid message matching the schema' do
      allow(WaterDrop::SyncProducer).to receive(:call)
      expect {
        described_class.produce(valid_message)
      }.not_to raise_error
    end

    it 'raises an error for a message that does not match the schema' do
      expect {
        described_class.produce(invalid_message)
      }.to raise_error(/Invalid message schema/)
    end
  end
end 