# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KafkaService do
  let(:valid_message) { { company_id: 12345, requested_at: '2025-06-16T12:00:00Z' } }
  let(:invalid_message) { { company_id: 'not-an-integer' } }
  let(:mock_producer) { double('KafkaProducer') }

  before do
    # Mock Karafka producer
    allow(Karafka).to receive(:respond_to?).and_return(true)
    allow(Karafka).to receive(:producer).and_return(mock_producer)
    allow(mock_producer).to receive(:produce_sync)
  end

  describe '.produce' do
    it 'accepts a valid message and sends it via Karafka producer' do
      expect(mock_producer).to receive(:produce_sync).with(
        topic: 'kafka_service',
        payload: valid_message.to_json,
        key: nil
      )

      expect {
        described_class.produce(valid_message)
      }.not_to raise_error
    end

    it 'accepts a message with a key' do
      expect(mock_producer).to receive(:produce_sync).with(
        topic: 'kafka_service',
        payload: valid_message.to_json,
        key: 'test-key'
      )

      expect {
        described_class.produce(valid_message, key: 'test-key')
      }.not_to raise_error
    end

    it 'handles missing Karafka gracefully' do
      allow(Karafka).to receive(:respond_to?).and_return(false)
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Karafka producer not available, message not sent to kafka_service")

      expect {
        described_class.produce(valid_message)
      }.not_to raise_error
    end
  end
end
