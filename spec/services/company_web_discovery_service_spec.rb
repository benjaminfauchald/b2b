require 'rails_helper'

RSpec.describe CompanyWebDiscoveryService do
  let(:company) { create(:company, company_name: 'Test Company AS', business_city: 'Oslo') }
  let(:service) { described_class.new(company_id: company.id) }

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        ServiceConfiguration.find_or_create_by(service_name: 'company_web_discovery') do |config|
          config.active = true
          config.refresh_interval_hours = 2160 # 90 days
        end
      end

      context 'when company needs web discovery' do
        before do
          allow(company).to receive(:needs_service?).with('company_web_discovery').and_return(true)
        end

        context 'with successful web discovery' do
          before do
            # Stub environment variables
            allow(ENV).to receive(:[]).and_call_original
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_API_KEY').and_return('test-api-key')
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_ENGINE_ID').and_return('test-engine-id')
            allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')

            # Stub Google Custom Search API
            stub_google_search_success
            # Stub URL validation
            stub_url_validation_success
            # Stub OpenAI validation
            stub_openai_validation_success
          end

          it 'discovers and updates web presence' do
            result = service.perform

            expect(result).to be_success
            expect(result.data[:discovered_pages]).to be_present
            expect(result.data[:discovered_pages].first[:url]).to eq('https://testcompany.no')
            expect(result.data[:discovered_pages].first[:confidence]).to eq(85)

            company.reload
            expect(company.website).to eq('https://testcompany.no')
            expect(company.web_pages).to be_present
          end

          it 'creates a successful audit log' do
            expect {
              service.perform
            }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('company_web_discovery')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.metadata['pages_found']).to eq(2)
          end

          it 'updates web_discovery_updated_at timestamp' do
            freeze_time do
              service.perform
              expect(company.reload.web_discovery_updated_at).to eq(Time.current)
            end
          end

          it 'handles multiple domain variations' do
            service.perform

            company.reload
            pages = company.web_pages
            expect(pages.map { |p| p['url'] }).to include('https://testcompany.no')
            expect(pages.map { |p| p['url'] }).to include('https://testcompany.com')
          end
        end

        context 'when no websites found' do
          before do
            stub_google_search_empty
          end

          it 'handles empty results gracefully' do
            result = service.perform

            expect(result).to be_success
            expect(result.message).to include('No websites found')

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['pages_found']).to eq(0)
          end
        end

        context 'with Google API error' do
          before do
            # Stub environment variables
            allow(ENV).to receive(:[]).and_call_original
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_API_KEY').and_return('test-api-key')
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_ENGINE_ID').and_return('test-engine-id')
            allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')

            stub_google_search_error
          end

          it 'handles API errors' do
            result = service.perform

            expect(result).not_to be_success
            expect(result.error).to include('Service error')
          end

          it 'creates audit log with error status' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('failed')
            expect(audit_log.error_message).to be_present
          end
        end

        context 'with rate limiting' do
          before do
            # Stub environment variables
            allow(ENV).to receive(:[]).and_call_original
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_API_KEY').and_return('test-api-key')
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_ENGINE_ID').and_return('test-engine-id')
            allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')

            stub_google_search_rate_limit
          end

          it 'handles rate limits gracefully' do
            result = service.perform

            expect(result).not_to be_success
            expect(result.error).to include('rate limit')
            expect(result.data[:retry_after]).to eq(3600)
          end
        end

        context 'with domain validation' do
          before do
            # Stub environment variables
            allow(ENV).to receive(:[]).and_call_original
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_API_KEY').and_return('test-api-key')
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_ENGINE_ID').and_return('test-engine-id')
            allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')

            stub_google_search_with_invalid_urls
            stub_url_validation_mixed
            stub_openai_validation_success
          end

          it 'validates and filters invalid URLs' do
            result = service.perform

            expect(result).to be_success

            company.reload
            pages = company.web_pages
            valid_urls = pages.map { |p| p['url'] }

            expect(valid_urls).to include('https://valid-domain.com')
            expect(valid_urls).not_to include('not-a-valid-url')
            expect(valid_urls).not_to include('invalid domain')
          end
        end

        context 'when APIs are not configured' do
          before do
            allow(ENV).to receive(:[]).and_call_original
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_API_KEY').and_return(nil)
            allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_ENGINE_ID').and_return(nil)
            allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
          end

          it 'returns empty results without error' do
            result = service.perform

            expect(result).to be_success
            expect(result.message).to include('No websites found')
          end
        end
      end

      context 'when company does not need update' do
        before do
          # Mock the service's needs_update? method directly
          allow_any_instance_of(CompanyWebDiscoveryService).to receive(:needs_update?).and_return(false)

          # Stub environment variables to avoid API calls (just in case)
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_API_KEY').and_return('test-api-key')
          allow(ENV).to receive(:[]).with('GOOGLE_SEARCH_ENGINE_ID').and_return('test-engine-id')
          allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')

          # Add a general stub to prevent any API calls (just in case)
          stub_request(:get, /customsearch\.googleapis\.com/)
            .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
        end

        it 'returns early without making API calls' do
          # The service should not make any Google API calls since the company doesn't need update
          result = service.perform

          expect(result).to be_success
          expect(result.message).to eq('Web discovery data is up to date')
        end

        it 'creates audit log with success status' do
          service.perform

          audit_log = ServiceAuditLog.last
          expect(audit_log.status).to eq('success')
          expect(audit_log.metadata['reason']).to eq('up_to_date')
          expect(audit_log.metadata['skipped']).to be true
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        config = ServiceConfiguration.find_or_create_by(service_name: 'company_web_discovery')
        config.update!(active: false)
      end

      it 'does not perform service' do
        result = service.perform

        expect(result).not_to be_success
        expect(result.error).to eq('Service is disabled')
      end
    end
  end

  describe '#clean_company_name' do
    it 'removes Norwegian legal entity suffixes' do
      expect(service.send(:clean_company_name, 'TEST COMPANY AS')).to eq('TEST COMPANY')
      expect(service.send(:clean_company_name, 'EXAMPLE BUSINESS ASA')).to eq('EXAMPLE BUSINESS')
      expect(service.send(:clean_company_name, 'SAMPLE DA')).to eq('SAMPLE')
    end

    it 'removes geographical suffixes' do
      expect(service.send(:clean_company_name, 'ELKJØP NORDIC AS')).to eq('ELKJØP')
      expect(service.send(:clean_company_name, 'MICROSOFT NORGE AS')).to eq('MICROSOFT')
      expect(service.send(:clean_company_name, 'IBM SCANDINAVIA AS')).to eq('IBM')
      expect(service.send(:clean_company_name, 'COCA COLA NORWAY AS')).to eq('COCA COLA')
    end

    it 'removes business descriptors' do
      expect(service.send(:clean_company_name, 'TEST GROUP AS')).to eq('TEST')
      expect(service.send(:clean_company_name, 'EXAMPLE HOLDING AS')).to eq('EXAMPLE')
      expect(service.send(:clean_company_name, 'SAMPLE INVEST AS')).to eq('SAMPLE')
    end

    it 'handles multiple suffixes correctly' do
      expect(service.send(:clean_company_name, 'REMA DISTRIBUSJON NORGE AS')).to eq('REMA DISTRIBUSJON')
      expect(service.send(:clean_company_name, 'UNO-X MOBILITY NORGE AS')).to eq('UNO-X MOBILITY')
      expect(service.send(:clean_company_name, 'ST1 NORGE AS')).to eq('ST1')
    end

    it 'preserves company names without suffixes' do
      expect(service.send(:clean_company_name, 'APPLE')).to eq('APPLE')
      expect(service.send(:clean_company_name, 'GOOGLE')).to eq('GOOGLE')
    end

    it 'handles case insensitivity' do
      expect(service.send(:clean_company_name, 'test company as')).to eq('test company')
      expect(service.send(:clean_company_name, 'Example Norge AS')).to eq('Example')
    end

    it 'cleans up multiple spaces' do
      expect(service.send(:clean_company_name, 'TEST   COMPANY   AS')).to eq('TEST COMPANY')
    end
  end

  describe '#generate_search_queries' do
    let(:company) { create(:company, company_name: 'ELKJØP NORDIC AS', business_city: 'Oslo', primary_industry_description: 'Electronics retail') }
    let(:service) { described_class.new(company_id: company.id) }

    it 'generates queries with cleaned company name' do
      queries = service.send(:generate_search_queries)

      expect(queries).to include('ELKJØP official website')
      expect(queries).to include('ELKJØP Norway')
      expect(queries).to include('ELKJØP Norge')
      expect(queries).to include('ELKJØP company')
    end

    it 'includes original company name as fallback' do
      queries = service.send(:generate_search_queries)

      expect(queries).to include('ELKJØP NORDIC AS official website')
    end

    it 'includes industry-specific queries' do
      queries = service.send(:generate_search_queries)

      expect(queries).to include('ELKJØP Electronics retail')
    end

    it 'includes location-specific queries' do
      queries = service.send(:generate_search_queries)

      expect(queries).to include('ELKJØP Oslo')
    end

    it 'removes duplicate queries' do
      queries = service.send(:generate_search_queries)

      expect(queries.uniq).to eq(queries)
    end
  end

  describe '#clean_url_to_base_domain' do
    it 'cleans URLs to base domain' do
      expect(service.send(:clean_url_to_base_domain, 'https://example.com/path/to/page')).to eq('https://example.com')
      expect(service.send(:clean_url_to_base_domain, 'https://www.example.com/path/to/page')).to eq('https://www.example.com')
      expect(service.send(:clean_url_to_base_domain, 'http://site.no/very/deep/path')).to eq('http://site.no')
    end

    it 'preserves www subdomain when present' do
      expect(service.send(:clean_url_to_base_domain, 'https://www.elkjop.no/products/phones')).to eq('https://www.elkjop.no')
    end

    it 'handles URLs without paths' do
      expect(service.send(:clean_url_to_base_domain, 'https://example.com')).to eq('https://example.com')
      expect(service.send(:clean_url_to_base_domain, 'https://www.example.com/')).to eq('https://www.example.com')
    end

    it 'handles query parameters and fragments' do
      expect(service.send(:clean_url_to_base_domain, 'https://example.com/path?param=value#section')).to eq('https://example.com')
    end

    it 'returns original URL if parsing fails' do
      invalid_url = 'not-a-valid-url'
      expect(service.send(:clean_url_to_base_domain, invalid_url)).to eq(invalid_url)
    end
  end

  describe '#needs_update?' do
    let(:service_config) do
      ServiceConfiguration.find_or_create_by(service_name: 'company_web_discovery') do |config|
        config.refresh_interval_hours = 2160 # 90 days
      end
    end

    context 'when web pages data is missing' do
      before do
        company.update!(website: nil, web_pages: nil)
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when web discovery is stale' do
      before do
        company.update!(
          web_discovery_updated_at: 91.days.ago,
          website: 'https://old-site.com'
        )
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when web discovery is recent' do
      before do
        service_config

        # Create a recent successful audit log to simulate recent service run
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'company_web_discovery',
          operation_type: 'discover',
          status: :success,
          started_at: 1.day.ago,
          completed_at: 1.day.ago,
          table_name: 'companies',
          record_id: company.id.to_s,
          columns_affected: [ 'web_pages' ],
          metadata: { 'pages_found' => 1 }
        )

        company.update!(
          web_discovery_updated_at: 1.day.ago,
          website: 'https://current-site.com',
          web_pages: [ { url: 'https://current-site.com' } ]
        )
      end

      it 'returns false' do
        expect(service.send(:needs_update?)).to be false
      end
    end
  end

  # Helper methods for stubbing API requests
  private

  def stub_google_search_success
    # Stub the Google Custom Search API HTTP request
    google_response = {
      "items" => [
        {
          "link" => "https://testcompany.no",
          "title" => "Test Company AS - Official Website",
          "snippet" => "Welcome to Test Company AS, a leading company in Norway..."
        },
        {
          "link" => "https://testcompany.com",
          "title" => "Test Company International",
          "snippet" => "Test Company AS international presence..."
        },
        {
          "link" => "https://facebook.com/testcompany",
          "title" => "Test Company on Facebook",
          "snippet" => "Follow Test Company on Facebook..."
        }
      ]
    }

    # Stub any GET request to Google Custom Search API
    stub_request(:get, /customsearch\.googleapis\.com\/customsearch\/v1/)
      .to_return(
        status: 200,
        body: google_response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_google_search_empty
    # Stub the Google Custom Search API HTTP request with empty results
    google_response = {
      "items" => nil
    }

    stub_request(:get, /customsearch\.googleapis\.com\/customsearch\/v1/)
      .to_return(
        status: 200,
        body: google_response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_google_search_error
    stub_request(:get, /customsearch\.googleapis\.com\/customsearch\/v1/)
      .to_raise(StandardError.new('API Error'))
  end

  def stub_google_search_rate_limit
    rate_limit_error = Google::Apis::RateLimitError.new('Rate limit exceeded')
    stub_request(:get, /customsearch\.googleapis\.com\/customsearch\/v1/)
      .to_raise(rate_limit_error)
  end

  def stub_google_search_with_invalid_urls
    google_response = {
      "items" => [
        {
          "link" => "not-a-valid-url",
          "title" => "Invalid URL",
          "snippet" => "This has an invalid URL..."
        },
        {
          "link" => "https://valid-domain.com",
          "title" => "Valid Domain",
          "snippet" => "This has a valid URL..."
        },
        {
          "link" => "invalid domain",
          "title" => "Another Invalid",
          "snippet" => "This also has an invalid URL..."
        }
      ]
    }

    stub_request(:get, /customsearch\.googleapis\.com\/customsearch\/v1/)
      .to_return(
        status: 200,
        body: google_response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_url_validation_success
    # Stub HTTParty for URL validation
    stub_request(:head, 'https://testcompany.no')
      .to_return(status: 200)
    stub_request(:head, 'https://testcompany.com')
      .to_return(status: 200)

    # Stub HTTParty for content fetching
    stub_request(:get, 'https://testcompany.no')
      .to_return(
        status: 200,
        body: '<html><head><title>Test Company AS</title><meta name="description" content="Official website of Test Company AS"></head><body>Welcome to Test Company</body></html>'
      )
    stub_request(:get, 'https://testcompany.com')
      .to_return(
        status: 200,
        body: '<html><head><title>Test Company International</title><meta name="description" content="Test Company global site"></head><body>Test Company International</body></html>'
      )
  end

  def stub_url_validation_mixed
    # Invalid URLs fail validation
    stub_request(:head, 'not-a-valid-url')
      .to_raise(URI::InvalidURIError)
    stub_request(:head, 'invalid domain')
      .to_raise(URI::InvalidURIError)

    # Valid URL succeeds
    stub_request(:head, 'https://valid-domain.com')
      .to_return(status: 200)
    stub_request(:get, 'https://valid-domain.com')
      .to_return(
        status: 200,
        body: '<html><head><title>Valid Domain</title></head><body>Content</body></html>'
      )
  end

  def stub_openai_validation_success
    openai_client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)

    openai_response = {
      "choices" => [
        {
          "message" => {
            "content" => "MATCH: Yes\nCONFIDENCE: 85\nREASONING: The website clearly belongs to Test Company AS based on the title, content, and Norwegian domain."
          }
        }
      ]
    }

    allow(openai_client).to receive(:chat).and_return(openai_response)
  end
end
