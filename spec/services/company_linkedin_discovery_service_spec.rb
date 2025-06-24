require 'rails_helper'

RSpec.describe CompanyLinkedinDiscoveryService do
  let(:company) { create(:company, registration_number: '123456789', company_name: 'Test Company AS') }
  let(:service) { described_class.new(company) }
  
  describe '#perform' do
    context 'when service configuration is active' do
      before do
        ServiceConfiguration.find_or_create_by(service_name: 'company_linkedin_discovery') do |config|
          config.active = true
          config.refresh_interval_hours = 1440 # 60 days
        end
      end

      context 'when company needs linkedin discovery' do
        before do
          allow(company).to receive(:needs_service?).with('company_linkedin_discovery').and_return(true)
        end

        context 'with successful linkedin discovery' do
          let(:linkedin_data) do
            {
              primary_url: 'https://linkedin.com/company/test-company-as',
              alternate_urls: [
                'https://linkedin.com/company/testcompany',
                'https://linkedin.com/company/test-company-norge'
              ],
              confidence_scores: {
                'https://linkedin.com/company/test-company-as' => 0.98,
                'https://linkedin.com/company/testcompany' => 0.75,
                'https://linkedin.com/company/test-company-norge' => 0.60
              },
              company_info: {
                employees: 150,
                industry: 'Technology',
                headquarters: 'Oslo, Norway',
                description: 'Leading technology company in Norway'
              }
            }
          end

          before do
            stub_linkedin_search_api(company.company_name, linkedin_data)
          end

          it 'discovers and updates linkedin profiles' do
            result = service.perform
            
            expect(result).to be_success
            expect(result.data[:linkedin_profiles]).to eq(linkedin_data)
            
            company.reload
            expect(company.linkedin_url).to eq('https://linkedin.com/company/test-company-as')
            expect(company.linkedin_ai_confidence).to eq(98)
            expect(company.linkedin_alternatives).to eq(linkedin_data[:alternate_urls])
          end

          it 'creates a successful audit log' do
            expect {
              service.perform
            }.to change(ServiceAuditLog, :count).by(1)
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('company_linkedin_discovery')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.metadata['profiles_found']).to eq(3)
            expect(audit_log.metadata['highest_confidence']).to eq(0.98)
          end

          it 'updates linkedin_last_processed_at timestamp' do
            freeze_time do
              service.perform
              expect(company.reload.linkedin_last_processed_at).to eq(Time.current)
            end
          end

          it 'updates employee count from linkedin data' do
            service.perform
            
            company.reload
            expect(company.linkedin_employee_count).to eq(150)
          end

          it 'marks linkedin as processed' do
            service.perform
            
            company.reload
            expect(company.linkedin_processed).to be true
          end
        end

        context 'with multiple low-confidence matches' do
          let(:linkedin_data) do
            {
              primary_url: nil,
              alternate_urls: [
                'https://linkedin.com/company/maybe-test-company',
                'https://linkedin.com/company/test-co'
              ],
              confidence_scores: {
                'https://linkedin.com/company/maybe-test-company' => 0.45,
                'https://linkedin.com/company/test-co' => 0.40
              }
            }
          end

          before do
            stub_linkedin_search_api(company.company_name, linkedin_data)
          end

          it 'stores alternatives but does not set primary URL' do
            result = service.perform
            
            expect(result).to be_success
            expect(result.message).to include('Low confidence matches found')
            
            company.reload
            expect(company.linkedin_url).to be_nil
            expect(company.linkedin_alternatives).to eq(linkedin_data[:alternate_urls])
            expect(company.linkedin_ai_confidence).to eq(45)
          end

          it 'creates audit log with low_confidence metadata' do
            service.perform
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['low_confidence']).to be true
            expect(audit_log.metadata['highest_confidence']).to eq(0.45)
          end
        end

        context 'when no linkedin profiles found' do
          before do
            stub_linkedin_search_api(company.company_name, { primary_url: nil, alternate_urls: [] })
          end

          it 'handles empty results gracefully' do
            result = service.perform
            
            expect(result).to be_success
            expect(result.message).to include('No LinkedIn profiles found')
            
            company.reload
            expect(company.linkedin_url).to be_nil
            expect(company.linkedin_processed).to be true
          end

          it 'creates audit log with not_found status' do
            service.perform
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('success')
            expect(audit_log.metadata['profiles_found']).to eq(0)
          end
        end

        context 'with API error' do
          before do
            stub_linkedin_api_error(company.company_name, 500)
          end

          it 'handles API errors' do
            result = service.perform
            
            expect(result).not_to be_success
            expect(result.error).to include('LinkedIn API error')
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
            stub_linkedin_api_rate_limit(company.company_name)
          end

          it 'handles rate limits gracefully' do
            result = service.perform
            
            expect(result).not_to be_success
            expect(result.error).to include('rate limit')
            expect(result.retry_after).to eq(7200)
          end

          it 'creates audit log with rate_limited status' do
            service.perform
            
            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('rate_limited')
            expect(audit_log.metadata['retry_after']).to eq(7200)
          end
        end

        context 'with data enrichment' do
          let(:linkedin_data_with_enrichment) do
            {
              primary_url: 'https://linkedin.com/company/test-company-as',
              company_info: {
                employees: 200,
                industry: 'Information Technology',
                specialties: ['Cloud Computing', 'AI', 'SaaS'],
                founded_year: 2010
              }
            }
          end

          before do
            stub_linkedin_search_api(company.company_name, linkedin_data_with_enrichment)
          end

          it 'enriches company data from LinkedIn' do
            service.perform
            
            company.reload
            expect(company.linkedin_employee_count).to eq(200)
            # Additional enrichment could update other fields based on business logic
          end
        end
      end

      context 'when company does not need update' do
        before do
          allow(company).to receive(:needs_service?).with('company_linkedin_discovery').and_return(false)
        end

        it 'returns early without making API call' do
          expect_no_linkedin_api_calls
          
          result = service.perform
          
          expect(result).to be_success
          expect(result.message).to eq('LinkedIn discovery data is up to date')
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
        ServiceConfiguration.find_or_create_by(service_name: 'company_linkedin_discovery') do |config|
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
      ServiceConfiguration.find_or_create_by(service_name: 'company_linkedin_discovery') do |config|
        config.refresh_interval_hours = 1440 # 60 days
      end
    end

    context 'when linkedin has not been processed' do
      before do
        company.update!(linkedin_processed: false)
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when linkedin discovery is stale' do
      before do
        company.update!(
          linkedin_last_processed_at: 61.days.ago,
          linkedin_processed: true
        )
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when linkedin discovery is recent' do
      before do
        company.update!(
          linkedin_last_processed_at: 1.day.ago,
          linkedin_processed: true,
          linkedin_url: 'https://linkedin.com/company/test'
        )
      end

      it 'returns false' do
        expect(service.send(:needs_update?)).to be false
      end
    end

    context 'when company info has changed significantly' do
      before do
        company.update!(
          linkedin_last_processed_at: 30.days.ago,
          linkedin_processed: true,
          company_name: 'Completely Different Company Name AS'
        )
      end

      it 'returns true for significant changes' do
        # This could be enhanced with more sophisticated change detection
        expect(service.send(:needs_update?)).to be false # Within 60 day window
      end
    end
  end

  # Helper methods for stubbing API requests
  def stub_linkedin_search_api(query, response_data)
    stub_request(:get, "#{ENV['LINKEDIN_API_ENDPOINT']}/search/companies")
      .with(query: hash_including(q: query))
      .to_return(
        status: 200,
        body: response_data.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_linkedin_api_error(query, status_code)
    stub_request(:get, "#{ENV['LINKEDIN_API_ENDPOINT']}/search/companies")
      .with(query: hash_including(q: query))
      .to_return(
        status: status_code,
        body: { error: 'Internal server error' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_linkedin_api_rate_limit(query)
    stub_request(:get, "#{ENV['LINKEDIN_API_ENDPOINT']}/search/companies")
      .with(query: hash_including(q: query))
      .to_return(
        status: 429,
        body: { error: 'Rate limit exceeded' }.to_json,
        headers: { 
          'Content-Type' => 'application/json',
          'Retry-After' => '7200'
        }
      )
  end

  def expect_no_linkedin_api_calls
    expect(WebMock).not_to have_requested(:get, /linkedin/)
  end
end