require 'rails_helper'

RSpec.describe DomainARecordTestJob, type: :job do
  # Clean up before each test to ensure isolated test environment
  before(:each) do
    Domain.delete_all
  end

  let!(:domain) { create(:domain, dns: true, www: nil) }

  describe 'job configuration' do
    it 'is configured to use DomainARecordTestingService queue' do
      expect(DomainARecordTestJob.queue_name).to eq('DomainARecordTestingService')
    end

    it 'has retry set to 0' do
      expect(DomainARecordTestJob.sidekiq_options['retry']).to eq(0)
    end
  end

  describe '#perform' do
    it 'calls DomainARecordTestingService.test_a_record with correct domain' do
      expect(DomainARecordTestingService).to receive(:test_a_record).with(domain)

      DomainARecordTestJob.perform_now(domain.id)
    end

    it 'finds domain by id and passes to service' do
      expect(Domain).to receive(:find).with(domain.id).and_return(domain)
      expect(DomainARecordTestingService).to receive(:test_a_record).with(domain)

      DomainARecordTestJob.perform_now(domain.id)
    end

    context 'when domain is not found' do
      it 'handles missing domain gracefully' do
        expect {
          DomainARecordTestJob.perform_now(99999)
        }.not_to raise_error
      end
    end

    context 'integration test' do
      before do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return('192.168.1.1')
      end

      it 'successfully processes domain A record test' do
        DomainARecordTestJob.perform_now(domain.id)

        expect(domain.reload.www).to be true
      end
    end

    context 'when service raises error' do
      before do
        allow(DomainARecordTestingService).to receive(:test_a_record).and_raise(StandardError, 'Service error')
      end

      it 'allows error to bubble up (no retry)' do
        expect {
          DomainARecordTestJob.perform_now(domain.id)
        }.to raise_error(StandardError, 'Service error')
      end
    end
  end
end
