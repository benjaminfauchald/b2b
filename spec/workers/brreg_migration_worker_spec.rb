require 'rails_helper'

RSpec.describe BrregMigrationWorker, type: :worker do
  let!(:brreg) { create(:brreg, organisasjonsnummer: '123456789', navn: 'Test AS') }

  it 'is queued in the brreg_migration queue' do
    expect(BrregMigrationWorker.sidekiq_options['queue']).to eq('brreg_migration')
  end

  it 'creates or updates a Company from a BRreg record' do
    expect {
      described_class.new.perform(brreg.organisasjonsnummer)
    }.to change { Company.count }.by(1)
    company = Company.find_by(registration_number: brreg.organisasjonsnummer)
    expect(company.company_name).to eq('Test AS')
  end

  it 'does nothing if BRreg record is missing' do
    expect {
      described_class.new.perform('999999999')
    }.not_to change { Company.count }
  end

  it 'logs and raises errors for Sidekiq retry' do
    allow(Brreg).to receive(:find_by).and_raise(StandardError, 'fail')
    expect(Rails.logger).to receive(:error).with(/Error processing Brreg organisasjonsnummer/)
    expect {
      described_class.new.perform('123456789')
    }.to raise_error(StandardError)
  end
end 