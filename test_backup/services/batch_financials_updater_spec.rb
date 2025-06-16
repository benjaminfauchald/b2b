# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BatchFinancialsUpdater do
  describe '.update_all' do
    let!(:companies) { create_list(:company, 3, :with_financial_data) }
    let!(:company_without_financials) { create(:company, financial_data_status: nil) }
    let!(:failed_company) { create(:company, :with_failed_financial_data) }
    let!(:stale_company) { create(:company, :with_stale_financial_data) }
    
    before do
      allow(CompanyFinancialsWorker).to receive(:perform_async)
    end
    
    it 'enqueues jobs for companies that need updates' do
      described_class.update_all
      
      # Should enqueue for:
      # - company_without_financials (no status)
      # - failed_company (failed status)
      # - stale_company (data is old)
      # Should skip companies that already have recent data
      
      expect(CompanyFinancialsWorker).to have_received(:perform_async).with(company_without_financials.id)
      expect(CompanyFinancialsWorker).to have_received(:perform_async).with(failed_company.id)
      expect(CompanyFinancialsWorker).to have_received(:perform_async).with(stale_company.id)
      
      companies.each do |company|
        expect(CompanyFinancialsWorker).not_to have_received(:perform_async).with(company.id)
      end
    end
    
    it 'respects the limit parameter' do
      described_class.update_all(limit: 2)
      
      expect(CompanyFinancialsWorker).to have_received(:perform_async).exactly(2).times
    end
    
    it 'respects the batch_size parameter' do
      allow(Company).to receive(:needs_financial_update).and_call_original
      
      described_class.update_all(batch_size: 1)
      
      expect(Company).to have_received(:needs_financial_update).ordered
      expect(Company).to have_received(:needs_financial_update).ordered
      expect(Company).to have_received(:needs_financial_update).ordered
    end
  end
  
  describe '.update_stale' do
    let!(:fresh_company) { create(:company, :with_financial_data) }
    let!(:stale_company1) { create(:company, :with_financial_data) }
    let!(:stale_company2) { create(:company, :with_financial_data) }
    
    before do
      allow(CompanyFinancialsWorker).to receive(:perform_async)
    end
    
    it 'enqueues jobs for companies with stale financial data' do
      described_class.update_stale
      
      expect(CompanyFinancialsWorker).to have_received(:perform_async).with(stale_company1.id)
      expect(CompanyFinancialsWorker).to have_received(:perform_async).with(stale_company2.id)
      expect(CompanyFinancialsWorker).not_to have_received(:perform_async).with(fresh_company.id)
    end
  end
  
  describe 'error handling' do
    let!(:company1) { create(:company, financial_data_status: nil) }
    let!(:company2) { create(:company, financial_data_status: nil) }
    
    before do
      allow(CompanyFinancialsWorker).to receive(:perform_async).and_raise(StandardError.new('Redis is down'))
      allow(Rails.logger).to receive(:error)
    end
    
    it 'logs errors but continues processing' do
      expect { described_class.update_all }.not_to raise_error
      
      expect(Rails.logger).to have_received(:error).with(/Error enqueuing update for company/).twice
    end
  end
end
