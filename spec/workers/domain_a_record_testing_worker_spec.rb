require 'rails_helper'

RSpec.describe DomainARecordTestingWorker, type: :worker do
  let(:service_name) { 'domain_a_record_testing' }
  let!(:service_config) do
    create(:service_configuration, 
           service_name: service_name,
           refresh_interval_hours: 24,
           batch_size: 100,
           active: true)
  end

  describe '#perform' do
    let(:domain) { create(:domain, domain: 'example.com', dns: true, www: nil) }

    context 'when domain exists' do
      before do
        allow(DomainARecordTestingService).to receive(:test_a_record).with(domain).and_return(true)
      end

      it 'calls DomainARecordTestingService.test_a_record' do
        expect(DomainARecordTestingService).to receive(:test_a_record).with(domain)
        described_class.new.perform(domain.id)
      end

      it 'updates domain www status' do
        described_class.new.perform(domain.id)
        expect(domain.reload.www).to be true
      end

      it 'creates audit log' do
        expect {
          described_class.new.perform(domain.id)
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq(service_name)
        expect(audit_log.status).to eq('success')
        expect(audit_log.auditable).to eq(domain)
        expect(audit_log.context).to include(
          'domain_name' => 'example.com',
          'www_status' => 'active'
        )
      end
    end

    context 'when domain does not exist' do
      it 'handles missing domain gracefully' do
        expect {
          described_class.new.perform(99999)
        }.not_to raise_error
      end
    end

    context 'when service raises error' do
      before do
        allow(DomainARecordTestingService).to receive(:test_a_record).with(domain).and_raise(StandardError, 'Service error')
      end

      it 'allows error to bubble up (no retry)' do
        expect {
          described_class.new.perform(domain.id)
        }.to raise_error(StandardError, 'Service error')
      end
    end
  end

  describe 'worker configuration' do
    it 'uses DomainARecordTestingService queue' do
      expect(described_class.get_sidekiq_options['queue']).to eq('DomainARecordTestingService')
    end

    it 'has retry set to 0' do
      expect(described_class.get_sidekiq_options['retry']).to eq(0)
    end
  end
end 