# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateCompanyFinancialsWorker, type: :worker do
  let(:company) { create(:company, registration_number: '123456789') }
  let(:service_double) { instance_double(CompanyFinancialsUpdater, call: true) }
  
  before do
    allow(CompanyFinancialsUpdater).to receive(:new).and_return(service_double)
  end
  
  describe '#perform' do
    context 'when the company exists' do
      it 'calls the CompanyFinancialsUpdater service' do
        described_class.new.perform(company.id)
        expect(CompanyFinancialsUpdater).to have_received(:new).with(company)
        expect(service_double).to have_received(:call)
      end
      
      it 'handles RateLimitError with retry' do
        allow(service_double).to receive(:call).and_raise(CompanyFinancialsUpdater::RateLimitError.new('Rate limit exceeded', 10))
        
        expect {
          described_class.new.perform(company.id)
        }.to raise_error(CompanyFinancialsUpdater::RateLimitError)
      end
    end
    
    context 'when the company does not exist' do
      it 'does not raise an error' do
        expect {
          described_class.new.perform(-1)
        }.not_to raise_error
      end
      
      it 'does not call the CompanyFinancialsUpdater service' do
        described_class.new.perform(-1)
        expect(CompanyFinancialsUpdater).not_to have_received(:new)
      end
    end
  end
  
  describe 'sidekiq_options' do
    it 'uses the financials queue' do
      expect(described_class.sidekiq_options['queue']).to eq('financials')
    end
    
    it 'has a retry limit of 5' do
      expect(described_class.sidekiq_options['retry']).to eq(5)
    end
  end
  
  describe 'sidekiq_retry_in' do
    let(:worker) { described_class.new }
    
    it 'uses retry_after for RateLimitError' do
      error = CompanyFinancialsUpdater::RateLimitError.new('Rate limit exceeded', 10)
      retry_in = described_class.sidekiq_retry_in_block.call(1, error)
      expect(retry_in).to eq(10)
    end
    
    it 'uses exponential backoff for other errors' do
      retry_in = described_class.sidekiq_retry_in_block.call(2, StandardError.new)
      expect(retry_in).to eq(30) # 10 * (2 + 1)
    end
  end
  
  describe 'sidekiq_retries_exhausted' do
    let(:company) { create(:company) }
    let(:error) { StandardError.new('Something went wrong') }
    let(:msg) { { 'args' => [company.id], 'retry_count' => 5 } }
    
    it 'updates the company status when retries are exhausted' do
      expect {
        described_class.sidekiq_retries_exhausted_block.call(msg, error)
      }.not_to change { company.reload.financial_data_status }
      
      company.reload
      expect(company.http_error).to eq(500)
      expect(company.http_error_message).to include('Max retries reached')
    end
    
    it 'does not raise an error if company is not found' do
      expect {
        described_class.sidekiq_retries_exhausted_block.call({ 'args' => [-1] }, error)
      }.not_to raise_error
    end
  end
end
