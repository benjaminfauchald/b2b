require 'rails_helper'

RSpec.describe CompanyWebDiscoveryService do
  let(:company) { create(:company, registration_number: '123456789', company_name: 'Test Company AS') }
  let(:service) { described_class.new(company) }
  
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
          let(:discovered_pages) do
            {
              main_website: 'https://testcompany.no',
              alternate_domains: [
                'https://testcompany.com',
                'https://test-company.no'
              ],
              social_media: {
                facebook: 'https://facebook.com/testcompany',
                twitter: 'https://twitter.com/testcompany',
                instagram: 'https://instagram.com/testcompany'
              },
              confidence_score: 0.95
            }
          end

          before do
            stub_web_search_api(company.company_name, discovered_pages)
          end

          it 'discovers and updates web presence' do
            result = service.perform
            
            expect(result).to be_success
            expect(result.data[:discovered_pages]).to eq(discovered_pages)
            
            company.reload
            expect(company.website).to eq('https://testcompany.no')
            expect(company.web_pages).to eq(discovered_pages.to_json)
          end

          it 'creates a successful audit log' do
            expect {
              service.perform
            }.to change(ServiceAuditLog, :count).by(1)
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('company_web_discovery')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.metadata['pages_found']).to eq(4)
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
            web_data = JSON.parse(company.web_pages)
            expect(web_data['alternate_domains']).to include('https://testcompany.com')
            expect(web_data['alternate_domains']).to include('https://test-company.no')
          end
        end

        context 'when no websites found' do
          before do
            stub_web_search_api(company.company_name, { main_website: nil, alternate_domains: [] })
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

        context 'with search API error' do
          before do
            stub_web_search_api_error(company.company_name, 500)
          end

          it 'handles API errors' do
            result = service.perform
            
            expect(result).not_to be_success
            expect(result.error).to include('Search API error')
          end

          it 'creates audit log with error status' do
            service.perform
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('error')
            expect(audit_log.error_message).to be_present
          end
        end

        context 'with rate limiting' do
          before do
            stub_web_search_api_rate_limit(company.company_name)
          end

          it 'handles rate limits gracefully' do
            result = service.perform
            
            expect(result).not_to be_success
            expect(result.error).to include('rate limit')
            expect(result.retry_after).to eq(3600)
          end
        end

        context 'with domain validation' do
          let(:discovered_pages) do
            {
              main_website: 'not-a-valid-url',
              alternate_domains: ['https://valid-domain.com', 'invalid domain']
            }
          end

          before do
            stub_web_search_api(company.company_name, discovered_pages)
          end

          it 'validates and filters invalid URLs' do
            result = service.perform
            
            expect(result).to be_success
            
            company.reload
            web_data = JSON.parse(company.web_pages)
            expect(web_data['alternate_domains']).to include('https://valid-domain.com')
            expect(web_data['alternate_domains']).not_to include('invalid domain')
            expect(web_data['invalid_urls']).to include('not-a-valid-url')
          end
        end
      end

      context 'when company does not need update' do
        before do
          allow(company).to receive(:needs_service?).with('company_web_discovery').and_return(false)
        end

        it 'returns early without making API call' do
          expect_no_web_search_api_calls
          
          result = service.perform
          
          expect(result).to be_success
          expect(result.message).to eq('Web discovery data is up to date')
        end

        it 'creates audit log with skipped status' do
          service.perform
          
          audit_log = ServiceAuditLog.last
          expect(audit_log.status).to eq('skipped')
          expect(audit_log.metadata['reason']).to eq('up_to_date')
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        ServiceConfiguration.find_or_create_by(service_name: 'company_web_discovery') do |config|
          config.active = false
        end
      end

      it 'does not perform service' do
        result = service.perform
        
        expect(result).not_to be_success
        expect(result.error).to eq('Service is disabled')
      end
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
        company.update!(
          web_discovery_updated_at: 1.day.ago,
          website: 'https://current-site.com',
          web_pages: { main_website: 'https://current-site.com' }.to_json
        )
      end

      it 'returns false' do
        expect(service.send(:needs_update?)).to be false
      end
    end
  end

  # Helper methods for stubbing API requests
  def stub_web_search_api(query, response_data)
    stub_request(:get, "#{ENV['SEARCH_API_ENDPOINT']}/search")
      .with(query: hash_including(q: query))
      .to_return(
        status: 200,
        body: response_data.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_web_search_api_error(query, status_code)
    stub_request(:get, "#{ENV['SEARCH_API_ENDPOINT']}/search")
      .with(query: hash_including(q: query))
      .to_return(
        status: status_code,
        body: { error: 'Internal server error' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_web_search_api_rate_limit(query)
    stub_request(:get, "#{ENV['SEARCH_API_ENDPOINT']}/search")
      .with(query: hash_including(q: query))
      .to_return(
        status: 429,
        body: { error: 'Rate limit exceeded' }.to_json,
        headers: { 
          'Content-Type' => 'application/json',
          'Retry-After' => '3600'
        }
      )
  end

  def expect_no_web_search_api_calls
    expect(WebMock).not_to have_requested(:get, /search/)
  end
end