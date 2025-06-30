require 'rails_helper'

RSpec.describe DomainARecordTestingService, type: :service do
  let(:service_config) do
    create(:service_configuration,
      service_name: "domain_a_record_testing",
      active: true
    )
  end

  let(:domain) { create(:domain, dns: true, www: nil, a_record_ip: nil) }

  before do
    service_config
    allow(ENV).to receive(:[]).and_call_original
  end

  describe "Enhanced A Record Testing with IP Storage" do
    let(:service) { described_class.new(domain: domain) }

    describe "#perform" do
      context "when A record resolution succeeds" do
        let(:test_ip) { "192.168.1.100" }

        before do
          allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return(test_ip)
        end

        it "stores the resolved IP address in domain.a_record_ip" do
          result = service.perform

          expect(result.success?).to be true
          domain.reload
          expect(domain.a_record_ip).to eq(test_ip)
          expect(domain.www).to be true
        end

        it "creates audit log with IP address in metadata" do
          service.perform

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_a_record_testing"
          ).last

          expect(audit_log.status).to eq("success")
          expect(audit_log.metadata["a_record"]).to eq(test_ip)
          expect(audit_log.metadata["domain_name"]).to eq(domain.domain)
        end

        it "updates www status and IP in single operation" do
          expect(domain).to receive(:update_columns).with(www: true, a_record_ip: test_ip)
          service.perform
        end

        it "handles IPv6 addresses correctly" do
          ipv6_address = "2001:db8::1"
          allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return(ipv6_address)

          result = service.perform

          expect(result.success?).to be true
          domain.reload
          expect(domain.a_record_ip).to eq(ipv6_address)
          expect(domain.www).to be true
        end
      end

      context "when A record resolution fails" do
        before do
          allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(Resolv::ResolvError.new("Name or service not known"))
        end

        it "sets www to false and a_record_ip to nil" do
          result = service.perform

          expect(result.success?).to be true # Service completes successfully even if DNS fails
          domain.reload
          expect(domain.www).to be false
          expect(domain.a_record_ip).to be_nil
        end

        it "creates audit log with error details" do
          service.perform

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_a_record_testing"
          ).last

          expect(audit_log.status).to eq("success") # Service ran successfully
          expect(audit_log.metadata["test_result"]).to eq("no_records")
          expect(audit_log.metadata["error"]).to eq("A record resolution failed")
        end

        it "updates both www and a_record_ip columns" do
          expect(domain).to receive(:update_columns).with(www: false, a_record_ip: nil)
          service.perform
        end
      end

      context "when A record resolution times out" do
        before do
          allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_raise(Timeout::Error.new)
        end

        it "sets www to false and a_record_ip to nil" do
          result = service.perform

          expect(result.success?).to be true
          domain.reload
          expect(domain.www).to be false
          expect(domain.a_record_ip).to be_nil
        end

        it "creates audit log with timeout error" do
          service.perform

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_a_record_testing"
          ).last

          expect(audit_log.metadata["test_result"]).to eq("timeout")
          expect(audit_log.metadata["error"]).to match(/timed out after \d+ seconds/)
        end
      end

      context "when domain already has A record data" do
        let(:old_ip) { "10.0.0.1" }
        let(:new_ip) { "192.168.1.1" }

        before do
          domain.update(www: true, a_record_ip: old_ip)
          allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return(new_ip)
        end

        it "updates to new IP address when resolution succeeds" do
          result = service.perform

          expect(result.success?).to be true
          domain.reload
          expect(domain.a_record_ip).to eq(new_ip)
          expect(domain.www).to be true
        end

        it "logs IP address change in metadata" do
          service.perform

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_a_record_testing"
          ).last

          expect(audit_log.metadata["a_record"]).to eq(new_ip)
          expect(audit_log.metadata["previous_a_record"]).to eq(old_ip)
        end
      end
    end

    describe "batch processing" do
      let!(:domains) do
        [
          create(:domain, domain: "test1.com", dns: true, www: nil),
          create(:domain, domain: "test2.com", dns: true, www: nil),
          create(:domain, domain: "test3.com", dns: true, www: nil)
        ]
      end

      let(:batch_service) { described_class.new(batch_size: 2) }

      before do
        # Mock DNS resolutions
        allow(Resolv).to receive(:getaddress).with("www.test1.com").and_return("1.1.1.1")
        allow(Resolv).to receive(:getaddress).with("www.test2.com").and_return("2.2.2.2")
        allow(Resolv).to receive(:getaddress).with("www.test3.com").and_raise(Resolv::ResolvError.new)
      end

      it "processes all domains and stores IP addresses" do
        result = batch_service.perform

        expect(result.success?).to be true

        domains[0].reload
        expect(domains[0].www).to be true
        expect(domains[0].a_record_ip).to eq("1.1.1.1")

        domains[1].reload
        expect(domains[1].www).to be true
        expect(domains[1].a_record_ip).to eq("2.2.2.2")

        domains[2].reload
        expect(domains[2].www).to be false
        expect(domains[2].a_record_ip).to be_nil
      end

      it "creates audit logs for all processed domains" do
        batch_service.perform

        domains.each do |domain|
          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_a_record_testing"
          ).last

          expect(audit_log).to be_present
          expect(audit_log.status).to eq("success")
        end
      end

      it "returns correct batch statistics" do
        result = batch_service.perform

        expect(result.data[:processed]).to eq(3)
        expect(result.data[:successful]).to eq(2) # 2 successful DNS resolutions
        expect(result.data[:failed]).to eq(1)    # 1 failed DNS resolution
        expect(result.data[:errors]).to eq(0)    # 0 service errors
      end
    end

    describe "backwards compatibility" do
      it "maintains existing behavior for www column" do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return("192.168.1.1")

        service.perform
        domain.reload

        # Existing behavior should still work
        expect(domain.www).to be true
        expect(domain.www?).to be true
      end

      it "doesn't break existing scopes and methods" do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return("192.168.1.1")
        service.perform

        domain.reload

        # Existing scopes should still work
        expect(Domain.www_active).to include(domain)
        expect(domain.www).to be true
      end
    end

    describe "error handling" do
      context "when service is disabled" do
        before do
          service_config.update(active: false)
        end

        it "returns error result" do
          result = service.perform
          expect(result.success?).to be false
          expect(result.error).to eq("Service is disabled")
        end
      end

      context "when database update fails" do
        before do
          allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return("192.168.1.1")
          allow(domain).to receive(:update_columns).and_raise(ActiveRecord::RecordInvalid.new(domain))
        end

        it "handles database errors gracefully" do
          expect { service.perform }.not_to raise_error
        end
      end
    end
  end

  describe "Legacy compatibility" do
    describe ".test_a_record" do
      it "still works as before but stores IP address" do
        allow(Resolv).to receive(:getaddress).with("www.#{domain.domain}").and_return("192.168.1.1")

        result = described_class.test_a_record(domain)

        expect(result).to be true
        domain.reload
        expect(domain.www).to be true
        expect(domain.a_record_ip).to eq("192.168.1.1")
      end
    end

    describe ".queue_all_domains" do
      let!(:domains) { create_list(:domain, 3, dns: true, www: nil) }

      it "queues all domains for A record testing" do
        expect(DomainARecordTestingWorker).to receive(:perform_async).exactly(3).times

        count = described_class.queue_all_domains
        expect(count).to eq(3)
      end
    end

    describe ".queue_100_domains" do
      let!(:domains) { create_list(:domain, 150, dns: true, www: nil) }

      it "queues only 100 domains" do
        expect(DomainARecordTestingWorker).to receive(:perform_async).exactly(100).times

        count = described_class.queue_100_domains
        expect(count).to eq(100)
      end
    end
  end
end
