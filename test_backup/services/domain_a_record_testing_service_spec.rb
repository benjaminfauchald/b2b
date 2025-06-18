require 'rails_helper'

RSpec.describe DomainARecordTestingService, type: :service do
  # Clean up before each test to ensure isolated test environment
  before(:each) do
    Domain.delete_all
  end

  let!(:domain_with_dns_true) { create(:domain, dns: true, www: nil) }
  let!(:domain_with_dns_false) { create(:domain, dns: false, www: nil) }
  let!(:domain_with_dns_nil) { create(:domain, dns: nil, www: nil) }
  let!(:domain_already_tested) { create(:domain, dns: true, www: true) }

  let(:service_name) { 'domain_a_record_testing' }
  let!(:service_config) do
    create(:service_configuration,
           service_name: service_name,
           refresh_interval_hours: 24,
           batch_size: 100,
           active: true)
  end

  describe '.test_a_record' do
    context 'when www.domain resolves successfully' do
      before do
        allow(Resolv).to receive(:getaddress).with("www.#{domain_with_dns_true.domain}").and_return('192.168.1.1')
      end

      it 'updates domain www field to true' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)

        expect(result).to be true
        expect(domain_with_dns_true.reload.www).to be true
      end

      it 'returns true' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)
        expect(result).to be true
      end
    end

    context 'when www.domain fails to resolve' do
      before do
        allow(Resolv).to receive(:getaddress).with("www.#{domain_with_dns_true.domain}").and_raise(Resolv::ResolvError)
      end

      it 'updates domain www field to false' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)

        expect(result).to be false
        expect(domain_with_dns_true.reload.www).to be false
      end

      it 'returns false' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)
        expect(result).to be false
      end
    end

    context 'when www.domain times out' do
      before do
        allow(Resolv).to receive(:getaddress).with("www.#{domain_with_dns_true.domain}").and_raise(Timeout::Error)
      end

      it 'updates domain www field to false' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)

        expect(result).to be false
        expect(domain_with_dns_true.reload.www).to be false
      end

      it 'returns false' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)
        expect(result).to be false
      end
    end

    context 'when other network error occurs' do
      before do
        allow(Resolv).to receive(:getaddress).with("www.#{domain_with_dns_true.domain}").and_raise(StandardError, 'Network error')
      end

      it 'updates domain www field to nil' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)

        expect(result).to be nil
        expect(domain_with_dns_true.reload.www).to be nil
      end

      it 'returns nil' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)
        expect(result).to be nil
      end
    end
  end

  describe '.queue_all_domains' do
    it 'queues only domains with dns=true and www=nil' do
      expect(DomainARecordTestingWorker).to receive(:perform_async).with(domain_with_dns_true.id)
      expect(DomainARecordTestingWorker).not_to receive(:perform_async).with(domain_with_dns_false.id)
      expect(DomainARecordTestingWorker).not_to receive(:perform_async).with(domain_with_dns_nil.id)
      expect(DomainARecordTestingWorker).not_to receive(:perform_async).with(domain_already_tested.id)

      DomainARecordTestingService.queue_all_domains
    end

    it 'does not queue domains with dns=false' do
      expect(DomainARecordTestingWorker).not_to receive(:perform_async).with(domain_with_dns_false.id)
      DomainARecordTestingService.queue_all_domains
    end

    it 'does not queue domains with dns=nil' do
      expect(DomainARecordTestingWorker).not_to receive(:perform_async).with(domain_with_dns_nil.id)
      DomainARecordTestingService.queue_all_domains
    end

    it 'does not queue domains already tested' do
      expect(DomainARecordTestingWorker).not_to receive(:perform_async).with(domain_already_tested.id)
      DomainARecordTestingService.queue_all_domains
    end

    it 'returns count of queued domains' do
      count = DomainARecordTestingService.queue_all_domains
      expect(count).to eq(1) # Only domain_with_dns_true should be queued
    end
  end

  describe '.queue_100_domains' do
    before do
      create_list(:domain, 150, dns: true, www: nil)
    end

    it 'only queues domains with dns=true and www=nil' do
      expect(DomainARecordTestingWorker).to receive(:perform_async).exactly(100).times
      DomainARecordTestingService.queue_100_domains
    end

    context 'when there are more than 100 domains to test' do
      it 'queues exactly 100 domains' do
        count = DomainARecordTestingService.queue_100_domains
        expect(count).to eq(100)
      end
    end

    context 'when there are fewer than 100 domains to test' do
      before do
        Domain.delete_all
        create_list(:domain, 50, dns: true, www: nil)
      end

      it 'queues all available domains' do
        count = DomainARecordTestingService.queue_100_domains
        expect(count).to eq(50)
      end
    end

    context 'when there are no domains to test' do
      before do
        Domain.delete_all
      end

      it 'queues no domains' do
        count = DomainARecordTestingService.queue_100_domains
        expect(count).to eq(0)
      end
    end
  end

  describe '#call' do
    context 'when domain needs testing' do
      it 'processes the domain' do
        service = described_class.new(domain: domain_with_dns_true)
        expect(service).to receive(:process_domain).with(domain_with_dns_true)
        service.call
      end
    end

    context 'when domain does not need testing' do
      it 'skips the domain' do
        service = described_class.new(domain: domain_already_tested)
        expect(service).not_to receive(:process_domain)
        service.call
      end
    end
  end

  describe '#process_domain' do
    let(:domain) { create(:domain) }
    let(:service) { described_class.new }

    before do
      allow(service).to receive(:service_name).and_return(service_name)
    end

    context 'when A record test succeeds' do
      it 'creates success audit log' do
        allow(service).to receive(:test_single_domain_for).with(domain).and_return(true)
        expect {
          service.send(:process_domain, domain)
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq(service_name)
        expect(audit_log.status).to eq('success')
        expect(audit_log.auditable).to eq(domain)
      end
    end

    context 'when A record test fails' do
      it 'creates failure audit log' do
        allow(service).to receive(:test_single_domain_for).with(domain).and_return(false)
        expect {
          service.send(:process_domain, domain)
        }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq(service_name)
        expect(audit_log.status).to eq('failed')
        expect(audit_log.auditable).to eq(domain)
      end
    end
  end
end
