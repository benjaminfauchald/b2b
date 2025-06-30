require 'rails_helper'
require 'ostruct'

RSpec.describe "Domain Web Content Extraction Integration", type: :request do
  let!(:a_record_service_config) do
    create(:service_configuration,
      service_name: "domain_a_record_testing",
      active: true
    )
  end

  let!(:web_content_service_config) do
    create(:service_configuration,
      service_name: "domain_web_content_extraction",
      active: true
    )
  end

  let!(:domain_ready_for_extraction) do
    create(:domain,
      dns: true,
      www: true,
      a_record_ip: "192.168.1.1"
    )
  end

  let!(:domain_without_a_record) do
    create(:domain,
      dns: true,
      www: false,
      a_record_ip: nil
    )
  end

  let!(:domain_needing_a_record_test) do
    create(:domain,
      dns: true,
      www: nil,
      a_record_ip: nil
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FIRECRAWL_API_KEY").and_return("test_api_key")
  end

  describe "Complete A Record → Web Content Extraction Flow" do
    let(:mock_firecrawl_response) do
      OpenStruct.new(
        success?: true,
        markdown: "# Example Domain\n\nThis domain is for use in illustrative examples in documents.",
        html: "<h1>Example Domain</h1><p>This domain is for use in illustrative examples in documents.</p>",
        metadata: {
          "title" => "Example Domain",
          "description" => "This domain is for use in illustrative examples",
          "url" => "https://needs-test.com",
          "statusCode" => 200
        },
        links: [ "https://example.com/about", "https://example.com/contact" ],
        screenshot_url: nil
      )
    end

    let(:mock_firecrawl_error_response) do
      OpenStruct.new(
        success?: false,
        error_description: "Connection timeout"
      )
    end

    before do
      allow(Firecrawl).to receive(:api_key)
      allow(Firecrawl).to receive(:scrape).and_return(mock_firecrawl_response)
    end

    describe "End-to-End Workflow" do
      it "processes domain from A record test to web content extraction" do
        # Step 1: A Record Test - Mock DNS resolution
        allow(Resolv).to receive(:getaddress).and_return("203.0.113.1")

        # Execute A Record Testing
        a_record_service = DomainARecordTestingService.new(domain: domain_needing_a_record_test)
        a_record_result = a_record_service.perform

        expect(a_record_result.success?).to be true

        # Verify A Record results
        domain_needing_a_record_test.reload
        expect(domain_needing_a_record_test.www).to be true
        expect(domain_needing_a_record_test.a_record_ip).to eq("203.0.113.1")

        # Step 2: Web Content Extraction
        web_content_service = DomainWebContentExtractionService.new(domain: domain_needing_a_record_test)
        web_content_result = web_content_service.perform

        expect(web_content_result.success?).to be true

        # Verify Web Content results
        domain_needing_a_record_test.reload
        expect(domain_needing_a_record_test.web_content_data).to be_present
        expect(domain_needing_a_record_test.web_content_data["content"]).to include("Example Domain")
        expect(domain_needing_a_record_test.web_content_data["title"]).to eq("Example Domain")
      end

      it "creates complete audit trail for both services" do
        # Mock DNS resolution
        allow(Resolv).to receive(:getaddress).and_return("203.0.113.1")

        # Execute both services
        DomainARecordTestingService.new(domain: domain_needing_a_record_test).perform
        DomainWebContentExtractionService.new(domain: domain_needing_a_record_test).perform

        # Verify A Record audit log
        a_record_audit = ServiceAuditLog.where(
          auditable: domain_needing_a_record_test,
          service_name: "domain_a_record_testing"
        ).last

        expect(a_record_audit.status).to eq("success")
        expect(a_record_audit.metadata["a_record"]).to eq("203.0.113.1")
        expect(a_record_audit.metadata["domain_name"]).to eq(domain_needing_a_record_test.domain)

        # Verify Web Content audit log
        web_content_audit = ServiceAuditLog.where(
          auditable: domain_needing_a_record_test,
          service_name: "domain_web_content_extraction"
        ).last

        expect(web_content_audit.status).to eq("success")
        expect(web_content_audit.metadata["url"]).to eq("https://#{domain_needing_a_record_test.domain}")
        expect(web_content_audit.metadata["extraction_success"]).to be true
        expect(web_content_audit.completed_at).to be > a_record_audit.completed_at
      end

      it "handles A record failure gracefully without attempting web extraction" do
        # Mock DNS resolution failure
        allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError.new)

        # Execute A Record Testing
        a_record_service = DomainARecordTestingService.new(domain: domain_needing_a_record_test)
        a_record_result = a_record_service.perform

        expect(a_record_result.success?).to be true # Service completed successfully

        domain_needing_a_record_test.reload
        expect(domain_needing_a_record_test.www).to be false
        expect(domain_needing_a_record_test.a_record_ip).to be_nil

        # Attempt Web Content Extraction (should fail prerequisite check)
        web_content_service = DomainWebContentExtractionService.new(domain: domain_needing_a_record_test)
        web_content_result = web_content_service.perform

        expect(web_content_result.success?).to be false
        expect(web_content_result.error).to match(/does not have.*a record/i)

        # Verify no web content was stored
        domain_needing_a_record_test.reload
        expect(domain_needing_a_record_test.web_content_data).to be_nil
      end
    end

    describe "Batch Processing Integration" do
      let!(:batch_domains) do
        [
          create(:domain, dns: true, www: nil),
          create(:domain, dns: true, www: nil),
          create(:domain, dns: true, www: nil)
        ]
      end

      it "processes complete workflow for multiple domains" do
        # Clear any existing domains except the one we need to preserve
        Domain.where.not(id: domain_ready_for_extraction.id).destroy_all

        # Create exactly 3 domains for this test
        domain1 = create(:domain, dns: true, www: nil)
        domain2 = create(:domain, dns: true, www: nil)
        domain3 = create(:domain, dns: true, www: nil)

        # Mock DNS resolutions - first 2 succeed, 3rd fails
        allow(Resolv).to receive(:getaddress) do |domain_url|
          case domain_url
          when "www.#{domain1.domain}"
            "1.1.1.1"
          when "www.#{domain2.domain}"
            "2.2.2.2"
          when "www.#{domain3.domain}"
            raise Resolv::ResolvError.new
          else
            raise "Unexpected domain: #{domain_url}"
          end
        end

        # Mock web content responses for any domain
        allow(Firecrawl).to receive(:scrape) do |url|
          OpenStruct.new(
            success?: true,
            markdown: "# Batch Test Domain\n\nBatch content for #{url}",
            html: "<html><head><title>Batch Test</title></head><body><h1>Batch Test</h1><p>Batch content for #{url}</p></body></html>",
            metadata: {
              "title" => "Batch Test",
              "description" => "Test content for batch processing",
              "url" => url,
              "statusCode" => 200
            },
            links: [],
            screenshot_url: nil
          )
        end

        # Execute A Record Testing for all domains
        a_record_service = DomainARecordTestingService.new(batch_size: 3)
        a_record_result = a_record_service.perform

        expect(a_record_result.success?).to be true
        expect(a_record_result.data[:processed]).to eq(3)
        expect(a_record_result.data[:successful]).to eq(2) # 2 successful DNS resolutions

        # Execute Web Content Extraction for domains with A records
        # Check which domains are ready for web content extraction
        domains_ready = Domain.needing_web_content
        # domain_ready_for_extraction was created at the beginning and has A record!
        expect(domains_ready.count).to eq(3) # batch1, batch2, and domain_ready_for_extraction

        web_content_service = DomainWebContentExtractionService.new(batch_size: 3)
        web_content_result = web_content_service.perform

        expect(web_content_result.success?).to be true
        # Three domains with A records should be processed (including domain_ready_for_extraction)
        expect(web_content_result.data[:processed]).to eq(3)
        expect(web_content_result.data[:successful]).to eq(3)
        expect(web_content_result.data[:skipped]).to eq(0) # No domains should be skipped since scope filters them

        # Verify final state
        domain1.reload
        expect(domain1.www).to be true
        expect(domain1.a_record_ip).to eq("1.1.1.1")
        expect(domain1.web_content_data).to be_present

        domain2.reload
        expect(domain2.www).to be true
        expect(domain2.a_record_ip).to eq("2.2.2.2")
        expect(domain2.web_content_data).to be_present

        domain3.reload
        expect(domain3.www).to be false
        expect(domain3.a_record_ip).to be_nil
        expect(domain3.web_content_data).to be_nil
      end
    end

    describe "Domain Scoping and Filtering" do
      it "correctly identifies domains needing each service" do
        # Domains needing A record testing
        domains_needing_a_record = Domain.where(dns: true, www: nil)
        expect(domains_needing_a_record).to include(domain_needing_a_record_test)
        expect(domains_needing_a_record).not_to include(domain_ready_for_extraction)
        expect(domains_needing_a_record).not_to include(domain_without_a_record)

        # Domains ready for web content extraction
        domains_ready_for_web_content = Domain.where(www: true).where.not(a_record_ip: nil)
        expect(domains_ready_for_web_content).to include(domain_ready_for_extraction)
        expect(domains_ready_for_web_content).not_to include(domain_without_a_record)
        expect(domains_ready_for_web_content).not_to include(domain_needing_a_record_test)
      end

      it "uses domain model methods for service eligibility" do
        expect(domain_ready_for_extraction.needs_web_content_extraction?).to be true
        expect(domain_without_a_record.needs_web_content_extraction?).to be false
        expect(domain_needing_a_record_test.needs_web_content_extraction?).to be false
      end
    end

    describe "Error Handling and Recovery" do
      it "handles Firecrawl API failures without breaking the workflow" do
        # Mock successful A record test
        allow(Resolv).to receive(:getaddress).and_return("203.0.113.1")

        # Execute A Record Testing first
        a_record_service = DomainARecordTestingService.new(domain: domain_needing_a_record_test)
        a_record_result = a_record_service.perform
        expect(a_record_result.success?).to be true

        # Mock Firecrawl failure
        allow(Firecrawl).to receive(:scrape).and_return(mock_firecrawl_error_response)

        # Execute Web Content Extraction
        web_content_service = DomainWebContentExtractionService.new(domain: domain_needing_a_record_test)
        web_content_result = web_content_service.perform

        expect(web_content_result.success?).to be false
        expect(web_content_result.error).to include("Connection timeout")

        # Verify A record data is preserved despite web content failure
        domain_needing_a_record_test.reload
        expect(domain_needing_a_record_test.www).to be true
        expect(domain_needing_a_record_test.a_record_ip).to eq("203.0.113.1")
        expect(domain_needing_a_record_test.web_content_data).to be_nil

        # Verify web content extraction was attempted but failed
        domain_needing_a_record_test.reload
        expect(domain_needing_a_record_test.web_content_data).to be_nil
      end

      it "allows retry of failed web content extraction" do
        # Setup domain with A record but failed web content extraction
        domain_ready_for_extraction.update(web_content_data: nil)
        create(:service_audit_log,
          auditable: domain_ready_for_extraction,
          service_name: "domain_web_content_extraction",
          status: "failed",
          completed_at: 1.hour.ago,
          started_at: 2.hours.ago,
          table_name: "domains",
          record_id: domain_ready_for_extraction.id.to_s,
          columns_affected: [ "web_content_data" ],
          metadata: { "error" => "Previous failure" }
        )

        # Mock successful Firecrawl response for retry
        allow(Firecrawl).to receive(:scrape).with(anything).and_return(mock_firecrawl_response)

        # Retry web content extraction
        retry_service = DomainWebContentExtractionService.new(domain: domain_ready_for_extraction)
        retry_result = retry_service.perform

        expect(retry_result.success?).to be true

        domain_ready_for_extraction.reload
        expect(domain_ready_for_extraction.web_content_data).to be_present
        expect(domain_ready_for_extraction.web_content_data["content"]).to include("Example Domain")

        # Verify successful audit log was created
        success_audit = ServiceAuditLog.where(
          auditable: domain_ready_for_extraction,
          service_name: "domain_web_content_extraction",
          status: "success"
        ).last

        expect(success_audit).to be_present
        expect(success_audit.completed_at).to be > 30.minutes.ago
      end
    end

    describe "Service Configuration Integration" do
      context "when A record service is disabled" do
        before { a_record_service_config.update(active: false) }

        it "prevents A record testing" do
          service = DomainARecordTestingService.new(domain: domain_needing_a_record_test)
          result = service.perform

          expect(result.success?).to be false
          expect(result.error).to eq("Service is disabled")
        end
      end

      context "when web content service is disabled" do
        before { web_content_service_config.update(active: false) }

        it "prevents web content extraction" do
          service = DomainWebContentExtractionService.new(domain: domain_ready_for_extraction)
          result = service.perform

          expect(result.success?).to be false
          expect(result.error).to eq("Service is disabled")
        end
      end
    end

    describe "Performance and Timing" do
      it "tracks execution times for both services" do
        # Mock DNS and Firecrawl
        allow(Resolv).to receive(:getaddress).and_return("203.0.113.1")
        allow(Firecrawl).to receive(:scrape).and_return(mock_firecrawl_response)

        # Execute services and measure timing
        start_time = Time.current

        DomainARecordTestingService.new(domain: domain_needing_a_record_test).perform
        DomainWebContentExtractionService.new(domain: domain_needing_a_record_test).perform

        end_time = Time.current

        # Verify audit logs have execution times
        a_record_audit = ServiceAuditLog.where(
          auditable: domain_needing_a_record_test,
          service_name: "domain_a_record_testing"
        ).last

        web_content_audit = ServiceAuditLog.where(
          auditable: domain_needing_a_record_test,
          service_name: "domain_web_content_extraction"
        ).last

        expect(a_record_audit.execution_time_ms).to be > 0
        expect(web_content_audit.execution_time_ms).to be > 0
        expect(a_record_audit.completed_at).to be_between(start_time, end_time)
        expect(web_content_audit.completed_at).to be_between(start_time, end_time)
      end
    end
  end
end
