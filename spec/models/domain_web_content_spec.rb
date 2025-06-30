require 'rails_helper'

RSpec.describe Domain, type: :model do
  describe "Web Content Extraction Features" do
    let(:domain) { create(:domain, domain: "example.com") }

    describe "a_record_ip column" do
      it "allows storing IP addresses" do
        domain.update(a_record_ip: "192.168.1.1")
        expect(domain.reload.a_record_ip).to eq("192.168.1.1")
      end

      it "allows IPv6 addresses" do
        ipv6 = "2001:db8::1"
        domain.update(a_record_ip: ipv6)
        expect(domain.reload.a_record_ip).to eq(ipv6)
      end

      it "allows nil values" do
        domain.update(a_record_ip: nil)
        expect(domain.reload.a_record_ip).to be_nil
      end

      it "stores the IP as string" do
        domain.update(a_record_ip: "10.0.0.1")
        expect(domain.a_record_ip).to be_a(String)
      end
    end

    describe "web_content_data column" do
      let(:sample_content_data) do
        {
          "title" => "Example Domain",
          "description" => "This domain is for use in illustrative examples",
          "content" => "Example Domain. This domain is for use in illustrative examples in documents.",
          "url" => "https://example.com",
          "extracted_at" => "2025-06-26T10:30:00Z",
          "markdown" => "# Example Domain\n\nThis domain is for use in illustrative examples in documents.",
          "links" => [ "https://www.iana.org/domains/example" ],
          "metadata" => {
            "status_code" => 200,
            "response_time_ms" => 150,
            "content_type" => "text/html",
            "charset" => "UTF-8"
          }
        }
      end

      it "allows storing JSON data" do
        domain.update(web_content_data: sample_content_data)
        expect(domain.reload.web_content_data).to eq(sample_content_data)
      end

      it "allows nested JSON structures" do
        nested_data = {
          "content" => { "body" => "text", "images" => [ "img1.jpg", "img2.png" ] },
          "seo" => { "title" => "SEO Title", "keywords" => [ "example", "domain" ] }
        }
        domain.update(web_content_data: nested_data)
        expect(domain.reload.web_content_data).to eq(nested_data)
      end

      it "allows nil values" do
        domain.update(web_content_data: nil)
        expect(domain.reload.web_content_data).to be_nil
      end

      it "allows empty hash" do
        domain.update(web_content_data: {})
        expect(domain.reload.web_content_data).to eq({})
      end

      it "preserves data types within JSON" do
        data_with_types = {
          "string" => "text",
          "number" => 42,
          "boolean" => true,
          "null" => nil,
          "array" => [ 1, 2, 3 ],
          "hash" => { "nested" => "value" }
        }
        domain.update(web_content_data: data_with_types)
        reloaded = domain.reload.web_content_data

        expect(reloaded["string"]).to be_a(String)
        expect(reloaded["number"]).to be_a(Integer)
        expect(reloaded["boolean"]).to be_a(TrueClass)
        expect(reloaded["null"]).to be_nil
        expect(reloaded["array"]).to be_a(Array)
        expect(reloaded["hash"]).to be_a(Hash)
      end
    end

    describe "service integration" do
      describe "#needs_web_content_extraction?" do
        it "returns true when domain has A record but no web content" do
          domain.update(www: true, a_record_ip: "192.168.1.1", web_content_data: nil)
          expect(domain.needs_web_content_extraction?).to be true
        end

        it "returns false when domain has no A record" do
          domain.update(www: false, a_record_ip: nil, web_content_data: nil)
          expect(domain.needs_web_content_extraction?).to be false
        end

        it "returns false when domain already has web content" do
          domain.update(www: true, a_record_ip: "192.168.1.1", web_content_data: { "title" => "Test" })
          expect(domain.needs_web_content_extraction?).to be false
        end

        it "returns true when web content exists but is old" do
          domain.update(www: true, a_record_ip: "192.168.1.1", web_content_data: { "title" => "Test" })

          # Create old successful audit log (over 30 days ago)
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: 31.days.ago
          )

          expect(domain.needs_web_content_extraction?).to be true
        end

        it "returns false when web content was recently extracted" do
          domain.update(www: true, a_record_ip: "192.168.1.1", web_content_data: { "title" => "Test" })

          # Create service configuration
          create(:service_configuration,
            service_name: "domain_web_content_extraction",
            active: true,
            refresh_interval_hours: 48  # 2 days
          )

          # Create recent successful audit log
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: 1.day.ago
          )

          expect(domain.needs_web_content_extraction?).to be false
        end
      end

      describe "#web_content_extracted_at" do
        it "returns nil when no extraction has been performed" do
          expect(domain.web_content_extracted_at).to be_nil
        end

        it "returns the completion time of most recent successful extraction" do
          extraction_time = 2.days.ago
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: extraction_time
          )

          expect(domain.web_content_extracted_at).to be_within(1.second).of(extraction_time)
        end

        it "ignores failed extraction attempts" do
          # Failed attempt
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "failed",
            completed_at: 1.day.ago,
            metadata: { "error" => "Failed to extract content" }
          )

          # Successful attempt
          success_time = 3.days.ago
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: success_time
          )

          expect(domain.web_content_extracted_at).to be_within(1.second).of(success_time)
        end
      end

      describe "#web_content_extraction_status" do
        it "returns :never_attempted when no extraction has been attempted" do
          expect(domain.web_content_extraction_status).to eq(:never_attempted)
        end

        it "returns :success when last extraction was successful" do
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: 1.day.ago
          )

          expect(domain.web_content_extraction_status).to eq(:success)
        end

        it "returns :failed when last extraction failed" do
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "failed",
            completed_at: 1.day.ago,
            metadata: { "error" => "Extraction failed" }
          )

          expect(domain.web_content_extraction_status).to eq(:failed)
        end

        it "returns :pending when extraction is currently running" do
          create(:service_audit_log,
            auditable: domain,
            service_name: "domain_web_content_extraction",
            status: "pending",
            started_at: 5.minutes.ago
          )

          expect(domain.web_content_extraction_status).to eq(:pending)
        end
      end
    end

    describe "scopes" do
      let!(:domain_with_a_record) { create(:domain, www: true, a_record_ip: "192.168.1.1") }
      let!(:domain_without_a_record) { create(:domain, www: false, a_record_ip: nil) }
      let!(:domain_with_content) { create(:domain, www: true, a_record_ip: "10.0.0.1", web_content_data: { "title" => "Test" }) }

      describe ".needing_web_content_extraction" do
        it "includes domains with A records but no web content" do
          result = Domain.needing_web_content_extraction
          expect(result).to include(domain_with_a_record)
          expect(result).not_to include(domain_without_a_record)
          expect(result).not_to include(domain_with_content)
        end

        it "includes domains with old web content" do
          # Create service configuration first
          create(:service_configuration,
            service_name: "domain_web_content_extraction",
            active: true,
            refresh_interval_hours: 24
          )

          # Create old successful extraction
          create(:service_audit_log,
            auditable: domain_with_content,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: 31.days.ago
          )

          result = Domain.needing_web_content_extraction
          expect(result).to include(domain_with_content)
        end

        it "excludes domains with recent web content" do
          # Create service configuration first
          create(:service_configuration,
            service_name: "domain_web_content_extraction",
            active: true,
            refresh_interval_hours: 24
          )

          # Create recent successful extraction (within refresh interval)
          create(:service_audit_log,
            auditable: domain_with_content,
            service_name: "domain_web_content_extraction",
            status: "success",
            completed_at: 1.hour.ago
          )

          result = Domain.needing_web_content_extraction
          expect(result).not_to include(domain_with_content)
        end
      end

      describe ".with_web_content" do
        it "returns domains that have web content data" do
          result = Domain.with_web_content
          expect(result).to include(domain_with_content)
          expect(result).not_to include(domain_with_a_record)
          expect(result).not_to include(domain_without_a_record)
        end
      end

      describe ".with_a_records" do
        it "returns domains that have A record IPs" do
          result = Domain.with_a_records
          expect(result).to include(domain_with_a_record)
          expect(result).to include(domain_with_content)
          expect(result).not_to include(domain_without_a_record)
        end
      end
    end
  end
end
