require 'rails_helper'
require 'resolv'

RSpec.describe DomainTestingService, type: :service do
  let!(:service_config) do
    create(:service_configuration, 
           service_name: 'domain_dns_testing_v1',
           refresh_interval_hours: 168,
           batch_size: 500,
           active: true)
  end

  describe '#initialize' do
    it 'sets default service name and action' do
      service = DomainTestingService.new
      expect(service.service_name).to eq('domain_dns_testing_v1')
      expect(service.action).to eq('test_dns')
    end

    it 'allows custom attributes' do
      service = DomainTestingService.new(batch_size: 100)
      expect(service.batch_size).to eq(100)
    end
  end

  describe '#call' do
    context 'when domains need testing' do
      let!(:domains) { create_list(:domain, 3, dns: nil) }

      before do
        # Mock successful DNS resolution
        allow_any_instance_of(DomainTestingService).to receive(:has_dns?).and_return(true)
      end

      it 'processes all domains needing testing' do
        service = DomainTestingService.new
        
        result = service.call
        
        expect(result[:processed]).to eq(3)
        expect(result[:successful]).to eq(3)
        expect(result[:failed]).to eq(0)
        expect(result[:errors]).to eq(0)
      end

      it 'creates audit logs for each domain' do
        service = DomainTestingService.new
        
        expect {
          service.call
        }.to change(ServiceAuditLog, :count).by(3)
        
        audit_logs = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1')
        expect(audit_logs.count).to eq(3)
        expect(audit_logs.all?(&:status_success?)).to be true
      end

      it 'updates domain dns status' do
        service = DomainTestingService.new
        
        service.call
        
        domains.each(&:reload)
        expect(domains.all? { |d| d.dns == true }).to be true
      end

      it 'stores DNS test details in audit log context' do
        domain = create(:domain, domain: 'example.com', dns: nil)
        service = DomainTestingService.new
        
        service.call
        
        audit_log = ServiceAuditLog.where(auditable: domain).last
        expect(audit_log.context).to include(
          'dns_result' => true,
          'domain_name' => 'example.com',
          'dns_status' => 'active'
        )
        expect(audit_log.context['test_duration_ms']).to be_a(Integer)
      end
    end

    context 'when no domains need testing' do
      it 'handles empty result gracefully' do
        # Create domain that was recently tested
        domain = create(:domain, dns: true)
        create(:service_audit_log,
               auditable: domain,
               service_name: 'domain_dns_testing_v1',
               status: :success,
               completed_at: 1.hour.ago)
        
        service = DomainTestingService.new
        result = service.call
        
        expect(result[:processed]).to eq(0)
      end
    end

    context 'when service configuration is inactive' do
      before { service_config.update!(active: false) }

      it 'does not process any domains' do
        create_list(:domain, 2, dns: nil)
        service = DomainTestingService.new
        
        result = service.call
        expect(result[:processed]).to eq(0)
      end
    end
  end

  describe '#test_domain_dns' do
    let(:service) { DomainTestingService.new }
    let(:domain) { create(:domain, domain: 'example.com', dns: nil) }

    context 'when DNS resolution succeeds' do
      before do
        allow(service).to receive(:has_dns?).and_return(true)
      end

      it 'updates domain with successful result' do
        result = service.send(:test_domain_dns, domain)
        
        domain.reload
        expect(domain.dns).to be true
        expect(result[:status]).to eq(:successful)
        expect(result[:dns_result]).to be true
      end

      it 'includes timing information in context' do
        result = service.send(:test_domain_dns, domain)
        
        expect(result[:context]['test_duration_ms']).to be_a(Integer)
        expect(result[:context]['test_duration_ms']).to be > 0
      end
    end

    context 'when DNS resolution fails' do
      before do
        allow(service).to receive(:has_dns?).and_raise(Resolv::ResolvError)
      end

      it 'handles Resolv::ResolvError correctly' do
        result = service.send(:test_domain_dns, domain)
        
        domain.reload
        expect(domain.dns).to be false
        expect(result[:status]).to eq(:failed)
        expect(result[:context]['error_type']).to eq('resolve_error')
      end
    end

    context 'when DNS resolution times out' do
      before do
        allow(service).to receive(:has_dns?).and_raise(Timeout::Error)
      end

      it 'handles Timeout::Error correctly' do
        result = service.send(:test_domain_dns, domain)
        
        domain.reload
        expect(domain.dns).to be false
        expect(result[:status]).to eq(:failed)
        expect(result[:context]['error_type']).to eq('timeout_error')
      end
    end

    context 'when network error occurs' do
      before do
        allow(service).to receive(:has_dns?).and_raise(StandardError, 'Network unreachable')
      end

      it 'handles network errors correctly' do
        result = service.send(:test_domain_dns, domain)
        
        domain.reload
        expect(domain.dns).to be nil  # Keep as untested for network errors
        expect(result[:status]).to eq(:errors)
        expect(result[:context]['error_type']).to eq('network_error')
      end
    end
  end

  describe 'legacy class methods' do
    let(:domain) { create(:domain, domain: 'example.com', dns: nil) }

    describe '.test_dns' do
      before do
        allow_any_instance_of(DomainTestingService).to receive(:has_dns?).and_return(true)
      end

      it 'maintains backward compatibility' do
        result = DomainTestingService.test_dns(domain)
        expect(result).to be true
        
        domain.reload
        expect(domain.dns).to be true
      end
    end

    describe '.queue_all_domains' do
      before do
        create_list(:domain, 5, dns: nil)
        allow(DomainTestJob).to receive(:perform_later)
      end

      it 'queues all domains needing testing' do
        count = DomainTestingService.queue_all_domains
        
        expect(count).to eq(5)
        expect(DomainTestJob).to have_received(:perform_later).exactly(5).times
      end
    end

    describe '.queue_100_domains' do
      before do
        create_list(:domain, 150, dns: nil)
        allow(DomainTestJob).to receive(:perform_later)
      end

      it 'queues only 100 domains' do
        count = DomainTestingService.queue_100_domains
        
        expect(count).to eq(100)
        expect(DomainTestJob).to have_received(:perform_later).exactly(100).times
      end
    end
  end

  describe '#has_dns?' do
    let(:service) { DomainTestingService.new }

    it 'returns true for valid domains' do
      allow(Resolv).to receive(:getaddress).with('example.com').and_return('93.184.216.34')
      
      result = service.send(:has_dns?, 'example.com')
      expect(result).to be true
    end

    it 'returns false for invalid domains' do
      allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError)
      
      result = service.send(:has_dns?, 'nonexistent.invalid')
      expect(result).to be false
    end

    it 'returns false on timeout' do
      allow(Resolv).to receive(:getaddress).and_raise(Timeout::Error)
      
      result = service.send(:has_dns?, 'slow-domain.com')
      expect(result).to be false
    end
  end

  describe 'audit log integration' do
    let(:service) { DomainTestingService.new }
    let(:domain) { create(:domain, dns: nil) }
    let(:audit_log) { create(:service_audit_log, auditable: domain, service_name: 'domain_dns_testing_v1') }

    it 'marks audit log as successful on success' do
      allow(service).to receive(:has_dns?).and_return(true)
      
      service.send(:test_domain_dns, domain, audit_log)
      
      audit_log.reload
      expect(audit_log.status_success?).to be true
      expect(audit_log.context['dns_result']).to be true
    end

    it 'marks audit log as failed on DNS error' do
      allow(service).to receive(:has_dns?).and_raise(Resolv::ResolvError)
      
      service.send(:test_domain_dns, domain, audit_log)
      
      audit_log.reload
      expect(audit_log.status_failed?).to be true
      expect(audit_log.context['error_type']).to eq('resolve_error')
    end
  end
end 