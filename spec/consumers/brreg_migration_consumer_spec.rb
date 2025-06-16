require 'rails_helper'

RSpec.describe BrregMigrationConsumer do
  let(:worker) { class_double('BrregMigrationWorker').as_stubbed_const }

  it 'enqueues a Sidekiq job for a valid message' do
    payload = { organisasjonsnummer: '123456789' }.to_json
    message = double(payload: payload)
    expect(worker).to receive(:perform_async).with('123456789')
    subject.consume([message])
  end

  it 'logs error for invalid JSON' do
    message = double(payload: 'not_json')
    expect(Rails.logger).to receive(:error).with(/Error processing BRreg message/)
    subject.consume([message])
  end
end 