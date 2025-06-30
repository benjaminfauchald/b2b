require 'rails_helper'

RSpec.describe DomainWebContentExtractionService, type: :service do
  let(:service_config) do
    create(:service_configuration,
      service_name: "domain_web_content_extraction",
      active: true
    )
  end

  let(:domain) { create(:domain, domain: "example.com", www: true, a_record_ip: "192.168.1.1") }

  before do
    service_config
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FIRECRAWL_API_KEY").and_return("test_api_key")
  end

  describe DomainWebContentExtractionService do
    let(:service) { described_class.new(domain: domain) }

    describe "#perform" do
      let(:mock_firecrawl_response) do
        {
          "success" => true,
          "data" => {
            "content" => "Example Domain. This domain is for use in illustrative examples in documents.",
            "markdown" => "# Example Domain\n\nThis domain is for use in illustrative examples in documents.",
            "html" => "<html><head><title>Example Domain</title></head><body><h1>Example Domain</h1><p>This domain is for use in illustrative examples in documents.</p></body></html>",
            "metadata" => {
              "title" => "Example Domain",
              "description" => "This domain is for use in illustrative examples",
              "url" => "https://example.com",
              "statusCode" => 200,
              "responseTime" => 150
            },
            "links" => [ "https://www.iana.org/domains/example" ]
          }
        }
      end

      let(:mock_scrape_result) do
        double("ScrapeResult",
          success?: true,
          markdown: "# Example Domain\n\nThis domain is for use in illustrative examples in documents.",
          html: "<html><head><title>Example Domain</title></head><body><h1>Example Domain</h1><p>This domain is for use in illustrative examples in documents.</p></body></html>",
          metadata: {
            "title" => "Example Domain",
            "description" => "This domain is for use in illustrative examples",
            "url" => "https://example.com",
            "statusCode" => 200,
            "responseTime" => 150
          },
          links: ["https://www.iana.org/domains/example"],
          screenshot_url: nil
        )
      end

      before do
        allow(Firecrawl).to receive(:api_key).with("test_api_key")
      end

      context "when Firecrawl extraction succeeds" do
        before do
          allow(Firecrawl).to receive(:scrape).with("https://example.com", { formats: ["markdown", "html", "links"] }).and_return(mock_scrape_result)
        end

        it "extracts and stores web content successfully" do
          result = service.perform

          expect(result.success?).to be true
          domain.reload

          expect(domain.web_content_data).to be_present
          expect(domain.web_content_data["content"]).to include("Example Domain")
          expect(domain.web_content_data["metadata"]["title"]).to eq("Example Domain")
          expect(domain.web_content_data["extracted_at"]).to be_present
        end

        it "creates successful audit log with extraction metadata" do
          service.perform

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_web_content_extraction"
          ).last

          expect(audit_log.status).to eq("success")
          expect(audit_log.metadata["domain_name"]).to eq("example.com")
          expect(audit_log.metadata["url"]).to eq("https://example.com")
          expect(audit_log.metadata["content_length"]).to be > 0
          expect(audit_log.metadata["extraction_success"]).to be true
        end

        it "stores normalized and structured content data" do
          service.perform
          domain.reload

          web_data = domain.web_content_data
          expect(web_data).to include(
            "content", "markdown", "html", "metadata", "links", "extracted_at"
          )
          expect(web_data["metadata"]).to include("title", "description", "statusCode")
        end

        it "handles both HTTP and HTTPS URLs" do
          # Test HTTP URL
          domain.update(domain: "http://example.com")
          allow(Firecrawl).to receive(:scrape).with("http://example.com", { formats: ["markdown", "html", "links"] }).and_return(mock_scrape_result)

          result = service.perform
          expect(result.success?).to be true
        end

        it "uses HTTPS by default" do
          expect(Firecrawl).to receive(:scrape).with("https://example.com", { formats: ["markdown", "html", "links"] })
          service.perform
        end
      end

      context "when Firecrawl extraction fails" do
        let(:mock_error_result) do
          double("ScrapeResult",
            success?: false,
            error_description: "Failed to fetch content"
          )
        end

        before do
          allow(Firecrawl).to receive(:scrape).with("https://example.com", { formats: ["markdown", "html", "links"] }).and_return(mock_error_result)
        end

        it "handles Firecrawl API errors gracefully" do
          result = service.perform

          expect(result.success?).to be false
          expect(result.error).to include("Failed to fetch content")

          domain.reload
          expect(domain.web_content_data).to be_nil
        end

        it "creates failed audit log with error details" do
          service.perform

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_web_content_extraction"
          ).last

          expect(audit_log.status).to eq("failed")
          expect(audit_log.metadata["error"]).to include("Failed to fetch content")
          expect(audit_log.metadata["extraction_success"]).to be false
        end
      end

      context "when Firecrawl API raises exception" do
        before do
          allow(Firecrawl).to receive(:scrape).and_raise(StandardError.new("Network error"))
        end

        it "handles exceptions and creates failed audit log" do
          result = service.perform

          expect(result.success?).to be false
          expect(result.error).to include("Network error")

          audit_log = ServiceAuditLog.where(
            auditable: domain,
            service_name: "domain_web_content_extraction"
          ).last

          expect(audit_log.status).to eq("failed")
          expect(audit_log.metadata["error"]).to include("Network error")
        end
      end

      context "when domain has no A record" do
        let(:domain) { create(:domain, domain: "example.com", www: false, a_record_ip: nil) }

        it "returns error for domains without A records" do
          result = service.perform

          expect(result.success?).to be false
          expect(result.error).to match(/domain does not have.*a record/i)
        end

        it "does not attempt Firecrawl extraction" do
          expect(Firecrawl).not_to receive(:scrape)
          service.perform
        end
      end

      context "when domain already has recent web content" do
        before do
          domain.update(web_content_data: { "title" => "Existing content" })
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: 1.hour.ago
          )
        end

        it "skips extraction for recently extracted content" do
          expect(Firecrawl).not_to receive(:scrape)
          
          result = service.perform

          expect(result.success?).to be true
          expect(result.message).to match(/recently extracted/i)
        end

        it "allows forced re-extraction" do
          service_with_force = described_class.new(domain: domain, force: true)
          allow(Firecrawl).to receive(:scrape).with("https://example.com", { formats: ["markdown", "html", "links"] }).and_return(mock_scrape_result)

          result = service_with_force.perform
          expect(result.success?).to be true
          expect(Firecrawl).to have_received(:scrape)
        end
      end
    end

    describe "batch processing" do
      let!(:domains) do
        [
          create(:domain, domain: "test1.com", www: true, a_record_ip: "1.1.1.1"),
          create(:domain, domain: "test2.com", www: true, a_record_ip: "2.2.2.2"),
          create(:domain, domain: "test3.com", www: false, a_record_ip: nil) # No A record
        ]
      end

      let(:batch_service) { described_class.new(batch_size: 2) }

      before do
        allow(Firecrawl).to receive(:api_key).with("test_api_key")

        # Mock successful responses for domains with A records
        allow(Firecrawl).to receive(:scrape).with("https://test1.com", { formats: ["markdown", "html", "links"] }).and_return(
          double("ScrapeResult", 
            success?: true,
            markdown: "Test1 content",
            html: "<p>Test1 content</p>",
            metadata: { "title" => "Test1" },
            links: [],
            screenshot_url: nil
          )
        )
        allow(Firecrawl).to receive(:scrape).with("https://test2.com", { formats: ["markdown", "html", "links"] }).and_return(
          double("ScrapeResult",
            success?: true,
            markdown: "Test2 content", 
            html: "<p>Test2 content</p>",
            metadata: { "title" => "Test2" },
            links: [],
            screenshot_url: nil
          )
        )
      end

      it "processes only domains with A records" do
        result = batch_service.perform

        expect(result.success?).to be true
        expect(result.data[:processed]).to eq(2) # Only domains with A records
        expect(result.data[:successful]).to eq(2)
        expect(result.data[:failed]).to eq(0)
        expect(result.data[:skipped]).to eq(0) # No skipped because scope filters them out
      end

      it "creates audit logs for all attempted extractions" do
        batch_service.perform

        # Should have audit logs for domains with A records
        expect(ServiceAuditLog.where(
          auditable: domains[0],
          service_name: "domain_web_content_extraction"
        )).to exist

        expect(ServiceAuditLog.where(
          auditable: domains[1],
          service_name: "domain_web_content_extraction"
        )).to exist

        # Should not have audit log for domain without A record
        expect(ServiceAuditLog.where(
          auditable: domains[2],
          service_name: "domain_web_content_extraction"
        )).not_to exist
      end
    end

    describe "configuration and environment" do
      context "when FIRECRAWL_API_KEY is not set" do
        before do
          allow(ENV).to receive(:[]).with("FIRECRAWL_API_KEY").and_return(nil)
        end

        it "returns configuration error" do
          result = service.perform
          expect(result.success?).to be false
          expect(result.error).to match(/firecrawl.*api.*key/i)
        end
      end

      context "when service is disabled" do
        before do
          service_config.update(active: false)
        end

        it "returns service disabled error" do
          result = service.perform
          expect(result.success?).to be false
          expect(result.error).to eq("Service is disabled")
        end
      end
    end

    describe "URL handling" do
      let(:mock_scrape_result) do
        double("ScrapeResult",
          success?: true,
          markdown: "# Example Domain\n\nThis domain is for use in illustrative examples in documents.",
          html: "<html><head><title>Example Domain</title></head><body><h1>Example Domain</h1><p>This domain is for use in illustrative examples in documents.</p></body></html>",
          metadata: {
            "title" => "Example Domain",
            "description" => "This domain is for use in illustrative examples",
            "url" => "https://example.com",
            "statusCode" => 200,
            "responseTime" => 150
          },
          links: ["https://www.iana.org/domains/example"],
          screenshot_url: nil
        )
      end
      
      it "handles domains with special characters" do
        domain.update(domain: "åäö-example.com")
        allow(Firecrawl).to receive(:scrape).with("https://åäö-example.com", { formats: ["markdown", "html", "links"] }).and_return(mock_scrape_result)

        result = service.perform
        expect(result.success?).to be true
      end

      it "handles domains with ports" do
        domain.update(domain: "example.com:8080")
        allow(Firecrawl).to receive(:scrape).with("https://example.com:8080", { formats: ["markdown", "html", "links"] }).and_return(mock_scrape_result)

        result = service.perform
        expect(result.success?).to be true
      end

      it "handles subdomains correctly" do
        domain.update(domain: "www.example.com")
        allow(Firecrawl).to receive(:scrape).with("https://www.example.com", { formats: ["markdown", "html", "links"] }).and_return(mock_scrape_result)

        result = service.perform
        expect(result.success?).to be true
      end
    end

    describe "content validation and processing" do
      let(:malformed_response) do
        double("ScrapeResult",
          success?: true,
          markdown: nil,
          html: nil,
          metadata: {},
          links: [],
          screenshot_url: nil
        )
      end

      before do
        allow(Firecrawl).to receive(:scrape).and_return(malformed_response)
      end

      it "handles malformed Firecrawl responses" do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to match(/no content found/i)
      end

      it "validates required content fields" do
        response_without_content = double("ScrapeResult",
          success?: true,
          markdown: "",
          html: "",
          metadata: { "title" => "Test" },
          links: [],
          screenshot_url: nil
        )

        allow(Firecrawl).to receive(:scrape).and_return(response_without_content)

        result = service.perform
        expect(result.success?).to be false
      end
    end

    describe "legacy and queue methods" do
      let(:mock_scrape_result) do
        double("ScrapeResult",
          success?: true,
          markdown: "# Example Domain\n\nThis domain is for use in illustrative examples in documents.",
          html: "<html><head><title>Example Domain</title></head><body><h1>Example Domain</h1><p>This domain is for use in illustrative examples in documents.</p></body></html>",
          metadata: {
            "title" => "Example Domain",
            "description" => "This domain is for use in illustrative examples",
            "url" => "https://example.com",
            "statusCode" => 200,
            "responseTime" => 150
          },
          links: ["https://www.iana.org/domains/example"],
          screenshot_url: nil
        )
      end
      
      describe ".extract_web_content" do
        it "provides legacy interface" do
          allow(Firecrawl).to receive(:scrape).and_return(mock_scrape_result)

          result = described_class.extract_web_content(domain)
          expect(result.success?).to be true
        end
      end

      describe ".queue_all_domains" do
        let!(:domains_with_a_records) { create_list(:domain, 3, www: true, a_record_ip: "1.1.1.1") }
        let!(:domains_without_a_records) { create_list(:domain, 2, www: false, a_record_ip: nil) }

        it "queues only domains with A records" do
          expect(DomainWebContentExtractionWorker).to receive(:perform_async).exactly(3).times

          count = described_class.queue_all_domains
          expect(count).to eq(3)
        end
      end

      describe ".queue_batch_domains" do
        let!(:domains) { create_list(:domain, 150, www: true, a_record_ip: "1.1.1.1") }

        it "queues specified number of domains" do
          expect(DomainWebContentExtractionWorker).to receive(:perform_async).exactly(50).times

          count = described_class.queue_batch_domains(50)
          expect(count).to eq(50)
        end
      end
    end
  end
end
