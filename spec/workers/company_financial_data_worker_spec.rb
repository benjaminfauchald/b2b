require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe CompanyFinancialDataWorker, type: :worker do
  let(:company) { create(:company) }
  let(:worker) { described_class.new }

  describe 'Sidekiq configuration' do
    it 'is configured with correct queue' do
      expect(described_class.sidekiq_options['queue']).to eq('company_financial_data')
    end

    it 'has retry configuration' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#perform' do
    context 'with valid company' do
      let(:service_double) { instance_double(CompanyFinancialDataService) }
      let(:service_result) { OpenStruct.new(success?: true, data: { revenue: 1000000 }) }

      before do
        allow(CompanyFinancialDataService).to receive(:new).with(company).and_return(service_double)
        allow(service_double).to receive(:perform).and_return(service_result)
      end

      it 'calls the financial data service' do
        expect(service_double).to receive(:perform)
        worker.perform(company.id)
      end

      it 'passes the correct company to the service' do
        expect(CompanyFinancialDataService).to receive(:new).with(company)
        worker.perform(company.id)
      end

      it 'logs successful execution' do
        expect(Rails.logger).to receive(:info).with(/Successfully processed financial data for company #{company.id}/)
        worker.perform(company.id)
      end
    end

    context 'with non-existent company' do
      it 'logs error and returns early' do
        non_existent_id = 999999
        expect(Rails.logger).to receive(:error).with(/Company not found: #{non_existent_id}/)
        expect { worker.perform(non_existent_id) }.not_to raise_error
      end

      it 'does not call the service' do
        expect(CompanyFinancialDataService).not_to receive(:new)
        worker.perform(999999)
      end
    end

    context 'when service fails' do
      let(:service_double) { instance_double(CompanyFinancialDataService) }
      let(:service_result) { OpenStruct.new(success?: false, error: 'API connection failed') }

      before do
        allow(CompanyFinancialDataService).to receive(:new).with(company).and_return(service_double)
        allow(service_double).to receive(:perform).and_return(service_result)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Failed to process financial data for company #{company.id}: API connection failed/)
        worker.perform(company.id)
      end

      it 'does not raise error (allows Sidekiq retry)' do
        expect { worker.perform(company.id) }.not_to raise_error
      end
    end

    context 'when service raises exception' do
      let(:service_double) { instance_double(CompanyFinancialDataService) }

      before do
        allow(CompanyFinancialDataService).to receive(:new).with(company).and_return(service_double)
        allow(service_double).to receive(:perform).and_raise(StandardError, 'Unexpected error')
      end

      it 'logs the exception' do
        expect(Rails.logger).to receive(:error).with(/Error in CompanyFinancialDataWorker/)
        expect { worker.perform(company.id) }.to raise_error(StandardError)
      end

      it 're-raises the exception for Sidekiq retry' do
        expect { worker.perform(company.id) }.to raise_error(StandardError, 'Unexpected error')
      end
    end

    context 'with Sidekiq testing' do
      it 'can be enqueued' do
        expect {
          described_class.perform_async(company.id)
        }.to change(described_class.jobs, :size).by(1)
      end

      it 'enqueues with correct arguments' do
        described_class.perform_async(company.id)
        expect(described_class.jobs.last['args']).to eq([company.id])
      end

      it 'can be performed inline' do
        Sidekiq::Testing.inline! do
          service_double = instance_double(CompanyFinancialDataService)
          allow(CompanyFinancialDataService).to receive(:new).and_return(service_double)
          allow(service_double).to receive(:perform).and_return(OpenStruct.new(success?: true))
          
          expect(service_double).to receive(:perform)
          described_class.perform_async(company.id)
        end
      end
    end
  end

  describe 'error handling' do
    context 'with rate limit error' do
      let(:service_double) { instance_double(CompanyFinancialDataService) }
      let(:service_result) { OpenStruct.new(success?: false, error: 'Rate limit exceeded', retry_after: 3600) }

      before do
        allow(CompanyFinancialDataService).to receive(:new).with(company).and_return(service_double)
        allow(service_double).to receive(:perform).and_return(service_result)
      end

      it 'logs rate limit information' do
        expect(Rails.logger).to receive(:warn).with(/Rate limited for company #{company.id}, retry after 3600 seconds/)
        worker.perform(company.id)
      end

      it 'could reschedule the job' do
        # This could be enhanced to actually reschedule based on retry_after
        worker.perform(company.id)
      end
    end
  end
end