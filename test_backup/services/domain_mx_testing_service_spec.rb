require 'rails_helper'

RSpec.describe DomainMxTestingService, type: :service do
  let(:service_name) { 'domain_mx_testing' }
  let!(:service_config) do
    create(:service_configuration, 
           service_name: service_name,
           refresh_interval_hours: 24,
           batch_size: 100,
           active: true)
  end

  describe '#call' do
    context 'when domains need testing' do
      let!(:domains) { create_list(:domain, 3, dns: true, www: true, mx: nil) }

      before do
        # Mock successful MX resolution for all domains
        allow_any_instance_of(DomainMxTestingService).to receive(:check_mx_record).and_return(true)
        allow_any_instance_of(DomainMxTestingService).to receive(:perform_mx_test).and_return({ status: :success, mx_records: ['mail.example.com'], duration: 0.01 })
      end

      it 'processes all domains needing testing' do
        service = DomainMxTestingService.new
        
        result = service.call
        
        expect(result[:processed]).to eq(3)
        expect(result[:successful]).to eq(3)
        expect(result[:failed]).to eq(0)
        expect(result[:errors]).to eq(0)
      end

      it 'creates audit logs for each domain' do
        service = DomainMxTestingService.new
        
        expect {
          service.call
        }.to change(ServiceAuditLog, :count).by(3)
        
        audit_logs = ServiceAuditLog.where(service_name: service_name)
        expect(audit_logs.count).to eq(3)
        expect(audit_logs.all?(&:status_success?)).to be true
      end

      it 'updates domain mx status' do
        service = DomainMxTestingService.new
        
        service.call
        
        domains.each(&:reload)
        expect(domains.all? { |d| d.mx == true }).to be true
      end

      it 'stores MX test details in audit log context' do
        domain = create(:domain, domain: 'example.com', dns: true, www: true, mx: nil)
        service = DomainMxTestingService.new
        
        service.call
        
        audit_log = ServiceAuditLog.where(auditable: domain).last
        expect(audit_log.context).to include(
          'domain_name' => 'example.com',
          'dns' => true,
          'www' => true,
          'mx_result' => true,
          'status' => 'has_mx_record'
        )
      end
    end

    context 'when no domains need testing' do
      it 'handles empty result gracefully' do
        # Create domain that was recently tested
        domain = create(:domain, dns: true, www: true, mx: true)
        create(:service_audit_log,
               auditable: domain,
               service_name: service_name,
               status: :success,
               completed_at: 1.hour.ago)
        
        service = DomainMxTestingService.new
        result = service.call
        
        expect(result[:processed]).to eq(0)
      end
    end

    context 'when service configuration is inactive' do
      before { service_config.update!(active: false) }

      it 'does not process any domains' do
        create_list(:domain, 2, dns: true, www: true, mx: nil)
        service = DomainMxTestingService.new
        
        result = service.call
        expect(result[:processed]).to eq(0)
      end
    end
  end

  describe '#check_mx_record' do
    let(:service) { DomainMxTestingService.new }
    let(:domain) { create(:domain, domain: 'example.com') }

    context 'when MX resolution succeeds' do
      before do
        allow(Resolv::DNS).to receive(:new).and_return(
          double(getresources: [double(exchange: 'mail.example.com')])
        )
      end

      it 'returns true when MX records exist' do
        result = service.send(:check_mx_record, domain.domain)
        expect(result).to be true
      end
    end

    context 'when MX resolution fails' do
      before do
        allow(Resolv::DNS).to receive(:new).and_return(
          double(getresources: [])
        )
      end

      it 'returns false when no MX records exist' do
        result = service.send(:check_mx_record, domain.domain)
        expect(result).to be false
      end
    end

    context 'when DNS resolution times out' do
      it 'returns false on timeout' do
        resolver_double = double('Resolv::DNS')
        allow(resolver_double).to receive(:getresources).and_raise(Timeout::Error)
        allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
        result = service.send(:check_mx_record, domain.domain)
        expect(result).to be false
      end
    end

    context 'when DNS resolution fails' do
      it 'returns false on ResolvError' do
        resolver_double = double('Resolv::DNS')
        allow(resolver_double).to receive(:getresources).and_raise(Resolv::ResolvError)
        allow(Resolv::DNS).to receive(:new).and_return(resolver_double)
        result = service.send(:check_mx_record, domain.domain)
        expect(result).to be false
      end
    end
  end

  describe 'legacy class methods' do
    let(:domain) { create(:domain, domain: 'example.com', dns: true, www: true, mx: nil) }

    describe '.test_mx' do
      before do
        allow_any_instance_of(DomainMxTestingService).to receive(:check_mx_record).and_return(true)
        allow_any_instance_of(DomainMxTestingService).to receive(:perform_mx_test).and_return({ status: :success, mx_records: ['mail.example.com'], duration: 0.01 })
      end

      it 'maintains backward compatibility' do
        result = DomainMxTestingService.test_mx(domain)
        expect(result).to be true
        
        domain.reload
        expect(domain.mx).to be true
      end
    end

    describe '.queue_all_domains' do
      before do
        create_list(:domain, 5, dns: true, www: true, mx: nil)
        allow(DomainMxTestingWorker).to receive(:perform_async)
      end

      it 'queues all domains needing testing' do
        count = DomainMxTestingService.queue_all_domains
        
        expect(count).to eq(5)
        expect(DomainMxTestingWorker).to have_received(:perform_async).exactly(5).times
      end
    end

    describe '.queue_100_domains' do
      before do
        create_list(:domain, 150, dns: true, www: true, mx: nil)
        allow(DomainMxTestingWorker).to receive(:perform_async)
      end

      it 'queues only 100 domains' do
        count = DomainMxTestingService.queue_100_domains
        
        expect(count).to eq(100)
        expect(DomainMxTestingWorker).to have_received(:perform_async).exactly(100).times
      end
    end
  end
end 