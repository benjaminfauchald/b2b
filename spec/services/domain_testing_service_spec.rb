require 'rails_helper'
require 'resolv'

RSpec.describe DomainTestingService do
  describe '#test_dns' do
    let(:domain) { create(:domain, domain: 'example.com', dns: nil) }

    context 'when domain has DNS record' do
      before do
        allow(Resolv).to receive(:getaddress).with('example.com').and_return('1.2.3.4')
      end

      it 'returns true for valid domain' do
        result = described_class.test_dns(domain)
        expect(result).to be true
      end

      it 'updates domain.dns field to true' do
        described_class.test_dns(domain)
        expect(domain.reload.dns).to be true
      end
    end

    context 'when domain has no DNS record (Resolv::ResolvError)' do
      before do
        allow(Resolv).to receive(:getaddress).with('example.com').and_raise(Resolv::ResolvError)
      end

      it 'returns false for invalid domain' do
        result = described_class.test_dns(domain)
        expect(result).to be false
      end

      it 'updates domain.dns field to false' do
        described_class.test_dns(domain)
        expect(domain.reload.dns).to be false
      end
    end

    context 'when DNS lookup fails with other errors' do
      before do
        allow(Resolv).to receive(:getaddress).with('example.com').and_raise(SocketError, 'Network error')
      end

      it 'returns nil for network errors' do
        result = described_class.test_dns(domain)
        expect(result).to be_nil
      end

      it 'updates domain.dns field to nil' do
        described_class.test_dns(domain)
        expect(domain.reload.dns).to be_nil
      end
    end
  end

  describe '#queue_all_domains' do
    let!(:unchecked_domain1) { create(:domain, domain: 'unchecked1.com', dns: nil) }
    let!(:unchecked_domain2) { create(:domain, domain: 'unchecked2.com', dns: nil) }
    let!(:checked_domain_true) { create(:domain, domain: 'good.com', dns: true) }
    let!(:checked_domain_false) { create(:domain, domain: 'bad.com', dns: false) }

    it 'only enqueues domains where dns field is null' do
      expect(DomainTestJob).to receive(:perform_later).with(unchecked_domain1.id)
      expect(DomainTestJob).to receive(:perform_later).with(unchecked_domain2.id)
      expect(DomainTestJob).not_to receive(:perform_later).with(checked_domain_true.id)
      expect(DomainTestJob).not_to receive(:perform_later).with(checked_domain_false.id)

      described_class.queue_all_domains
    end

    it 'returns count of queued jobs (only null dns)' do
      allow(DomainTestJob).to receive(:perform_later)
      result = described_class.queue_all_domains
      expect(result).to eq(2)
    end

    it 'handles empty unchecked domains gracefully' do
      Domain.where(dns: nil).destroy_all
      result = described_class.queue_all_domains
      expect(result).to eq(0)
    end

    context 'with mixed domain states' do
      it 'queues only unchecked domains from mixed set' do
        expect(DomainTestJob).to receive(:perform_later).exactly(2).times
        result = described_class.queue_all_domains
        expect(result).to eq(2)
      end
    end
  end

  describe '#queue_100_domains' do
    context 'with fewer than 100 unchecked domains' do
      let!(:unchecked_domain1) { create(:domain, domain: 'unchecked1.com', dns: nil) }
      let!(:unchecked_domain2) { create(:domain, domain: 'unchecked2.com', dns: nil) }
      let!(:checked_domain_true) { create(:domain, domain: 'good.com', dns: true) }
      let!(:checked_domain_false) { create(:domain, domain: 'bad.com', dns: false) }

      it 'only enqueues domains where dns field is null' do
        expect(DomainTestJob).to receive(:perform_later).with(unchecked_domain1.id)
        expect(DomainTestJob).to receive(:perform_later).with(unchecked_domain2.id)
        expect(DomainTestJob).not_to receive(:perform_later).with(checked_domain_true.id)
        expect(DomainTestJob).not_to receive(:perform_later).with(checked_domain_false.id)

        described_class.queue_100_domains
      end

      it 'returns count of queued jobs (only null dns)' do
        allow(DomainTestJob).to receive(:perform_later)
        result = described_class.queue_100_domains
        expect(result).to eq(2)
      end
    end

    context 'with more than 100 unchecked domains' do
      before do
        # Create 150 unchecked domains
        150.times do |i|
          create(:domain, domain: "test#{i}.com", dns: nil)
        end
      end

      it 'only queues 100 domains' do
        expect(DomainTestJob).to receive(:perform_later).exactly(100).times
        result = described_class.queue_100_domains
        expect(result).to eq(100)
      end

      it 'returns count of 100' do
        allow(DomainTestJob).to receive(:perform_later)
        result = described_class.queue_100_domains
        expect(result).to eq(100)
      end
    end

    context 'with no unchecked domains' do
      before do
        Domain.where(dns: nil).destroy_all
      end

      it 'returns 0 when no domains to queue' do
        result = described_class.queue_100_domains
        expect(result).to eq(0)
      end
    end
  end
end 