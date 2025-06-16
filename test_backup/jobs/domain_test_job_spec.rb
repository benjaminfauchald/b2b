require 'rails_helper'

RSpec.describe DomainTestJob, type: :job do
  describe '#perform' do
    let(:domain) { create(:domain, domain: 'example.com', dns: nil) }
    let(:service_name) { 'domain_testing' }

    context 'with valid domain ID' do
      it 'calls DomainTestingService.test_dns' do
        expect(DomainTestingService).to receive(:test_dns).with(domain)
        described_class.new.perform(domain.id)
      end

      it 'updates domain record with result' do
        # Mock successful DNS resolution
        allow(DomainTestingService).to receive(:test_dns).with(domain).and_return(true)
        described_class.new.perform(domain.id)
        expect(domain.reload.dns).to be true
      end
    end

    context 'with invalid domain ID' do
      it 'handles missing domain gracefully' do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end

      it 'does not raise error' do
        expect(DomainTestingService).not_to receive(:test_dns)
        described_class.new.perform(999999)
      end
    end

    context 'when service raises error' do
      before do
        allow(DomainTestingService).to receive(:test_dns).with(domain).and_raise(StandardError, 'Network timeout')
      end

      it 'does not re-raise error' do
        expect { described_class.new.perform(domain.id) }.not_to raise_error
      end
    end
  end

  describe 'job configuration' do
    it 'has retry count of 0' do
      expect(described_class.sidekiq_options_hash['retry']).to eq(0)
    end

    it 'uses DomainTestingService queue' do
      expect(described_class.queue_name).to eq('DomainTestingService')
    end
  end
end 