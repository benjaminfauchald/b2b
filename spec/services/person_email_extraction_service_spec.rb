require 'rails_helper'

RSpec.describe PersonEmailExtractionService, type: :service do
  let(:company) { create(:company, website: "https://example.com") }
  let(:person) { create(:person, name: "John Doe", company: company) }
  let(:service) { described_class.new(person: person) }

  # Mock Hunter.io API responses
  let(:successful_hunter_response) do
    {
      "data" => {
        "first_name" => "John",
        "last_name" => "Doe",
        "email" => "john.doe@example.com",
        "score" => 95,
        "domain" => "example.com",
        "accept_all" => false,
        "position" => "Software Engineer",
        "company" => "Example Company",
        "sources" => [
          {
            "domain" => "example.com",
            "uri" => "https://example.com/team",
            "extracted_on" => "2024-01-01",
            "last_seen_on" => "2024-01-01",
            "still_on_page" => true
          }
        ],
        "verification" => {
          "date" => "2024-01-01",
          "status" => "valid"
        }
      }
    }
  end

  let(:not_found_hunter_response) do
    {
      "data" => {
        "first_name" => "John",
        "last_name" => "Doe",
        "email" => nil,
        "score" => nil,
        "domain" => "example.com",
        "accept_all" => false,
        "position" => nil,
        "company" => nil,
        "sources" => [],
        "verification" => nil
      }
    }
  end

  let(:error_hunter_response) do
    {
      "errors" => [
        {
          "id" => "rate_limit_exceeded",
          "code" => 429,
          "details" => "Rate limit exceeded. Please wait before making another request."
        }
      ]
    }
  end

  before do
    # Create service configuration
    ServiceConfiguration.create!(
      service_name: "person_email_extraction",
      active: true,
      refresh_interval_hours: 24,
      batch_size: 100,
      retry_attempts: 3
    )

    # Mock Hunter.io API key - stub the method directly on the service
    allow_any_instance_of(PersonEmailExtractionService).to receive(:hunter_api_key).and_return('test_api_key')
  end

  describe '#perform' do
    context 'when service is active and person exists' do
      before do
        # Mock HTTParty request to Hunter.io API
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, parsed_response: successful_hunter_response)
        )
      end

      it 'successfully extracts email from Hunter.io' do
        result = service.perform

        expect(result.success?).to be true
        expect(result.data[:email]).to eq("john.doe@example.com")
        expect(result.data[:confidence]).to eq(95)
      end

      it 'updates person with extracted email' do
        service.perform

        person.reload
        expect(person.email).to eq("john.doe@example.com")
        expect(person.email_extracted_at).to be_present
        expect(person.email_data).to include(
          "email" => "john.doe@example.com",
          "confidence" => 95,
          "source" => "hunter_io",
          "verification_status" => "valid"
        )
      end

      it 'creates audit log with success status' do
        expect { service.perform }.to change { ServiceAuditLog.count }.by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq("person_email_extraction")
        expect(audit_log.status).to eq("success")
        expect(audit_log.auditable).to eq(person)
        expect(audit_log.metadata["email_found"]).to be true
        expect(audit_log.metadata["email"]).to eq("john.doe@example.com")
        expect(audit_log.metadata["confidence"]).to eq(95)
      end

      it 'calls Hunter.io API with correct parameters' do
        expected_params = {
          query: {
            domain: "example.com",
            first_name: "John",
            last_name: "Doe",
            api_key: "test_api_key"
          },
          timeout: 30
        }

        expect(HTTParty).to receive(:get).with(
          "https://api.hunter.io/v2/email-finder",
          expected_params
        ).and_return(double(success?: true, parsed_response: successful_hunter_response))

        service.perform
      end
    end

    context 'when Hunter.io finds no email' do
      before do
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, parsed_response: not_found_hunter_response)
        )
      end

      it 'returns success with no email found message' do
        result = service.perform

        expect(result.success?).to be true
        expect(result.message).to include("No email found")
      end

      it 'creates audit log indicating no email found' do
        service.perform

        audit_log = ServiceAuditLog.last
        expect(audit_log.status).to eq("success")
        expect(audit_log.metadata["email_found"]).to be false
        expect(audit_log.metadata["reason"]).to include("Hunter.io found no email")
      end

      it 'does not update person email field' do
        expect { service.perform }.not_to change { person.reload.email }
      end
    end

    context 'when Hunter.io API returns error' do
      before do
        allow(HTTParty).to receive(:get).and_return(
          double(success?: false, code: 429, parsed_response: error_hunter_response)
        )
      end

      it 'returns error result' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to include("Hunter.io API error")
      end

      it 'creates audit log with failure status' do
        service.perform

        audit_log = ServiceAuditLog.last
        expect(audit_log.status).to eq("failure")
        expect(audit_log.metadata["error_code"]).to eq(429)
        expect(audit_log.metadata["error_details"]).to include("Rate limit exceeded")
      end
    end

    context 'when person has no company or website' do
      let(:person_no_company) { create(:person, name: "Jane Doe", company: nil) }
      let(:service_no_company) { described_class.new(person: person_no_company) }

      it 'returns error for missing company' do
        result = service_no_company.perform

        expect(result.success?).to be false
        expect(result.error).to include("Company and website required")
      end

      context 'company without website' do
        let(:company_no_website) { create(:company, website: nil) }
        let(:person_no_website) { create(:person, name: "Jane Doe", company: company_no_website) }
        let(:service_no_website) { described_class.new(person: person_no_website) }

        it 'returns error for missing website' do
          result = service_no_website.perform

          expect(result.success?).to be false
          expect(result.error).to include("Company and website required")
        end
      end
    end

    context 'when person name cannot be parsed' do
      let(:person_no_last_name) { create(:person, name: "John", company: company) }
      let(:service_no_last_name) { described_class.new(person: person_no_last_name) }

      it 'returns error for invalid name format' do
        result = service_no_last_name.perform

        expect(result.success?).to be false
        expect(result.error).to include("Valid first and last name required")
      end
    end

    context 'when service is disabled' do
      before do
        ServiceConfiguration.find_by(service_name: "person_email_extraction")&.update!(active: false)
      end

      it 'returns error when service is disabled' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to eq("Service is disabled")
      end
    end

    context 'when HUNTER_API_KEY is missing' do
      before do
        allow_any_instance_of(PersonEmailExtractionService).to receive(:hunter_api_key).and_return(nil)
      end

      it 'returns error for missing API key' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to include("Hunter.io API key not configured")
      end
    end

    context 'when network timeout occurs' do
      before do
        allow(HTTParty).to receive(:get).and_raise(Timeout::Error.new("Request timeout"))
      end

      it 'handles timeout gracefully' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to include("Request timeout")
      end

      it 'creates audit log with failure status' do
        service.perform

        audit_log = ServiceAuditLog.last
        expect(audit_log.status).to eq("failure")
      end
    end

    context 'when JSON parsing fails' do
      before do
        allow(HTTParty).to receive(:get).and_return(
          double(success?: true, parsed_response: "invalid json")
        )
      end

      it 'handles invalid JSON response' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to include("Invalid response format")
      end
    end
  end

  describe 'private methods' do
    describe '#extract_domain' do
      it 'extracts domain from various URL formats' do
        service_instance = service

        expect(service_instance.send(:extract_domain, "https://www.example.com")).to eq("example.com")
        expect(service_instance.send(:extract_domain, "http://example.com/path")).to eq("example.com")
        expect(service_instance.send(:extract_domain, "www.example.com")).to eq("example.com")
        expect(service_instance.send(:extract_domain, "example.com")).to eq("example.com")
      end

      it 'returns nil for invalid URLs' do
        service_instance = service

        expect(service_instance.send(:extract_domain, "")).to be_nil
        expect(service_instance.send(:extract_domain, nil)).to be_nil
        expect(service_instance.send(:extract_domain, "not-a-url")).to eq("not-a-url")
      end
    end

    describe '#parse_person_name' do
      it 'parses various name formats correctly' do
        service_instance = service

        expect(service_instance.send(:parse_person_name, "John Doe")).to eq(["John", "Doe"])
        expect(service_instance.send(:parse_person_name, "John Michael Doe")).to eq(["John", "Doe"])
        expect(service_instance.send(:parse_person_name, "Dr. John Doe Jr.")).to eq(["John", "Doe"])
      end

      it 'returns nil for invalid names' do
        service_instance = service

        expect(service_instance.send(:parse_person_name, "John")).to be_nil
        expect(service_instance.send(:parse_person_name, "")).to be_nil
        expect(service_instance.send(:parse_person_name, nil)).to be_nil
      end
    end
  end
end