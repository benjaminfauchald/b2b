# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe FinancialsConsumer do
  let(:group_id) { 'test-group' }
  let(:consumer) { described_class.new(group_id: group_id) }
  let(:valid_payload) { { company_id: 12345, requested_at: '2025-06-16T12:00:00Z' } }
  let(:invalid_payload) { { company_id: 'not-an-integer' } }
  let(:valid_message) { OpenStruct.new(value: valid_payload.to_json, key: 'key1', offset: 1, partition: 0) }
  let(:invalid_message) { OpenStruct.new(value: invalid_payload.to_json, key: 'key2', offset: 2, partition: 0) }

  before do
    allow(consumer).to receive(:log_to_sct)
    allow(consumer).to receive(:handle_financials_updated).and_return(true)
  end

  describe '#process_message' do
    it 'processes a valid message matching the schema' do
      expect {
        consumer.send(:process_message, valid_message)
      }.not_to raise_error
    end

    it 'raises an error for a message that does not match the schema' do
      expect {
        consumer.send(:process_message, invalid_message)
      }.to raise_error(/Invalid message schema/)
    end
  end
end 