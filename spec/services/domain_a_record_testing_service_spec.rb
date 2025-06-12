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

    context 'when www.domain fails to resolve (ResolvError)' do
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
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
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
        
        expect(result).to be_nil
        expect(domain_with_dns_true.reload.www).to be_nil
      end

      it 'returns nil' do
        result = DomainARecordTestingService.test_a_record(domain_with_dns_true)
        expect(result).to be_nil
      end
    end
  end

  describe '.queue_all_domains' do
    before do
      # Create additional test domains
      create_list(:domain, 5, dns: true, www: nil)
      create_list(:domain, 3, dns: false, www: nil)
      create_list(:domain, 2, dns: nil, www: nil)
    end

    it 'queues only domains with dns=true and www=nil' do
      expect(DomainARecordTestJob).to receive(:perform_later).exactly(6).times # 1 + 5 domains with dns=true, www=nil
      
      result = DomainARecordTestingService.queue_all_domains
      expect(result).to eq(6)
    end

    it 'does not queue domains with dns=false' do
      expect(DomainARecordTestJob).to receive(:perform_later).exactly(6).times
      
      DomainARecordTestingService.queue_all_domains
    end

    it 'does not queue domains with dns=nil' do
      expect(DomainARecordTestJob).to receive(:perform_later).exactly(6).times
      
      DomainARecordTestingService.queue_all_domains
    end

    it 'does not queue domains already tested (www not nil)' do
      expect(DomainARecordTestJob).to receive(:perform_later).exactly(6).times
      
      DomainARecordTestingService.queue_all_domains
    end

    it 'returns count of queued domains' do
      allow(DomainARecordTestJob).to receive(:perform_later)
      
      result = DomainARecordTestingService.queue_all_domains
      expect(result).to eq(6)
    end
  end

  describe '.queue_100_domains' do
    context 'when there are more than 100 domains to test' do
      before do
        create_list(:domain, 150, dns: true, www: nil)
      end

      it 'queues exactly 100 domains' do
        expect(DomainARecordTestJob).to receive(:perform_later).exactly(100).times
        
        result = DomainARecordTestingService.queue_100_domains
        expect(result).to eq(100)
      end
    end

    context 'when there are fewer than 100 domains to test' do
      before do
        create_list(:domain, 50, dns: true, www: nil)
      end

      it 'queues all available domains' do
        expect(DomainARecordTestJob).to receive(:perform_later).exactly(51).times # 1 + 50
        
        result = DomainARecordTestingService.queue_100_domains
        expect(result).to eq(51)
      end
    end

    context 'when there are no domains to test' do
      before do
        Domain.update_all(www: true) # Mark all as tested
      end

      it 'queues no domains' do
        expect(DomainARecordTestJob).not_to receive(:perform_later)
        
        result = DomainARecordTestingService.queue_100_domains
        expect(result).to eq(0)
      end
    end

    it 'only queues domains with dns=true and www=nil' do
      create_list(:domain, 30, dns: true, www: nil)
      create_list(:domain, 30, dns: false, www: nil)
      create_list(:domain, 30, dns: nil, www: nil)
      create_list(:domain, 30, dns: true, www: true)

      expect(DomainARecordTestJob).to receive(:perform_later).exactly(31).times # 1 + 30 valid domains
      
      result = DomainARecordTestingService.queue_100_domains
      expect(result).to eq(31)
    end
  end
end 