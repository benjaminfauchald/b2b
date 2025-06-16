# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialsConsumer do
  let(:company) { create(:company, registration_number: '123456789') }
  let(:message) do
    instance_double(
      'Kafka::FetchedMessage',
      key: company.registration_number,
      value: {
        'event_type' => 'company_financials_updated',
        'company_id' => company.id,
        'registration_number' => company.registration_number,
        'timestamp' => Time.current.iso8601,
        'data' => {
          'ordinary_result' => 500_000,
          'annual_result' => 1_000_000,
          'operating_revenue' => 10_000_000,
          'operating_costs' => 9_000_000
        }
      }.to_json,
      offset: 1,
      partition: 0,
      topic: 'company_financials'
    )
  end
  
  let(:consumer) { described_class.new(group_id: 'test_group', topic: 'company_financials') }
  
  before do
    allow(consumer).to receive(:messages).and_return([message])
  end
  
  describe '#consume' do
    it 'processes the message and updates the company' do
      expect {
        consumer.consume
        company.reload
      }.to change(company, :ordinary_result).to(500_000)
        .and change(company, :annual_result).to(1_000_000)
        .and change(company, :operating_revenue).to(10_000_000)
        .and change(company, :operating_costs).to(9_000_000)
      audit_log = ServiceAuditLog.where(auditable: company, service_name: 'company_financials', status: :success).order(completed_at: :desc).first
      expect(audit_log).not_to be_nil
      expect(audit_log.changed_fields).to include('ordinary_result', 'annual_result', 'operating_revenue', 'operating_costs')
    end
    
    context 'when the company does not exist' do
      before { company.destroy }
      
      it 'raises an error' do
        expect { consumer.consume }.to raise_error(RuntimeError, /Company not found/)
      end
    end
    
    context 'when the message is invalid' do
      let(:message) do
        instance_double(
          'Kafka::FetchedMessage',
          key: 'invalid',
          value: 'invalid json',
          offset: 1,
          partition: 0,
          topic: 'company_financials'
        )
      end
      
      it 'raises a JSON parse error' do
        expect { consumer.consume }.to raise_error(JSON::ParserError)
      end
    end
  end
  
  describe '#process_message' do
    it 'handles unknown event types' do
      message = instance_double(
        'Kafka::FetchedMessage',
        key: 'test',
        value: { 'event_type' => 'unknown' }.to_json,
        offset: 1,
        partition: 0,
        topic: 'company_financials'
      )
      
      expect(Rails.logger).to receive(:warn).with(/Unknown event type/)
      
      consumer.send(:process_message, message)
    end
  end
end
