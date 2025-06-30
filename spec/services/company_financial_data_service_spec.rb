require 'rails_helper'

RSpec.describe CompanyFinancialDataService do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company, registration_number: '123456789', ordinary_result: nil) }
  let(:service) { described_class.new(company) }

  before do
    ENV['BRREG_API_ENDPOINT'] = 'https://api.brreg.no'
  end

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        config = ServiceConfiguration.find_or_create_by(service_name: 'company_financial_data')
        config.update!(
          active: true,
          refresh_interval_hours: 720 # 30 days
        )
      end

      context 'when company needs financial data update' do
        # No mocking needed - the company will naturally need service if no recent audit logs exist

        context 'with successful API response' do
          let(:financial_data) do
            {
              revenue: 1_000_000,
              profit: 100_000,
              equity: 500_000,
              total_assets: 2_000_000,
              current_assets: 800_000,
              fixed_assets: 1_200_000,
              current_liabilities: 300_000,
              long_term_liabilities: 700_000,
              year: 2023
            }
          end

          before do
            stub_financial_api_request(company.registration_number, financial_data)
          end

          it 'fetches and updates financial data' do
            result = service.perform

            expect(result).to be_success
            expect(result.data[:financial_data]).to eq(financial_data)

            company.reload
            expect(company.revenue).to eq(1_000_000)
            expect(company.profit).to eq(100_000)
            expect(company.equity).to eq(500_000)
          end

          it 'creates a successful audit log' do
            expect {
              service.perform
            }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('company_financial_data')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.metadata['api_response_code']).to eq(200)
          end

          it 'updates financial_data_updated_at timestamp' do
            freeze_time do
              service.perform
              expect(company.reload.financial_data_updated_at).to eq(Time.current)
            end
          end

          it 'tracks execution time in audit log' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.execution_time_ms).to be > 0
            expect(audit_log.started_at).to be_present
            expect(audit_log.completed_at).to be_present
          end
        end

        context 'with rate limit error' do
          before do
            stub_financial_api_rate_limit(company.registration_number)
          end

          it 'handles rate limit gracefully' do
            result = service.perform

            expect(result).not_to be_success
            expect(result.error).to include('rate limit')
            expect(result.data[:retry_after]).to eq(60)
          end

          it 'creates audit log with failed status and rate_limited metadata' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('rate_limited')
            expect(audit_log.error_message).to eq('API rate limit exceeded')
            expect(audit_log.metadata['rate_limited']).to be true
            expect(audit_log.metadata['retry_after']).to eq(60)
          end
        end

        context 'with API error' do
          before do
            stub_financial_api_error(company.registration_number, 500)
          end

          it 'handles API errors' do
            result = service.perform

            expect(result).not_to be_success
            expect(result.error).to include('API error')
          end

          it 'creates audit log with failed status' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('failed')
            expect(audit_log.error_message).to be_present
          end
        end

        context 'with invalid financial data' do
          before do
            # Return an empty array to simulate no financial data
            stub_request(:get, "https://api.brreg.no/regnskapsregisteret/regnskap/#{company.registration_number}")
              .to_return(
                status: 200,
                body: [].to_json,
                headers: { 'Content-Type' => 'application/json' }
              )
          end

          it 'handles empty financial data' do
            result = service.perform

            expect(result).to be_success
            expect(result.message).to eq('No financial data available for this company')
          end
        end
      end

      context 'when company does not need update' do
        before do
          # Create a recent successful audit log to make needs_service? return false
          ServiceAuditLog.create!(
            auditable: company,
            service_name: 'company_financial_data',
            operation_type: 'process',
            status: :success,
            table_name: 'companies',
            record_id: company.id.to_s,
            columns_affected: [ 'revenue', 'profit' ],
            metadata: { result: 'success' },
            started_at: 1.hour.ago,
            completed_at: 1.hour.ago
          )
        end

        it 'returns early without making API call' do
          expect_no_financial_api_calls

          result = service.perform

          expect(result).to be_success
          expect(result.message).to eq('Financial data is up to date')
        end

        it 'creates audit log with success status but skipped metadata' do
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
        config = ServiceConfiguration.find_or_create_by(service_name: 'company_financial_data')
        config.update!(active: false)
      end

      it 'does not perform service' do
        result = service.perform

        expect(result).not_to be_success
        expect(result.error).to eq('Service is disabled')
      end
    end
  end

  describe '#needs_update?' do
    before do
      ServiceConfiguration.find_or_create_by(service_name: 'company_financial_data') do |config|
        config.refresh_interval_hours = 720 # 30 days
      end
    end

    context 'when financial data is missing' do
      before do
        company.update!(revenue: nil, profit: nil)
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when financial data is stale' do
      before do
        company.update!(
          financial_data_updated_at: 31.days.ago,
          revenue: 1000
        )
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when financial data is recent' do
      before do
        company.update!(
          financial_data_updated_at: 1.day.ago,
          revenue: 1000
        )

        # Create a recent successful audit log
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'company_financial_data',
          operation_type: 'process',
          status: :success,
          table_name: 'companies',
          record_id: company.id.to_s,
          columns_affected: [ 'revenue', 'profit' ],
          metadata: { result: 'success' },
          started_at: 1.day.ago,
          completed_at: 1.day.ago
        )
      end

      it 'returns false' do
        expect(service.send(:needs_update?)).to be false
      end
    end
  end

  # Helper methods for stubbing API requests
  def stub_financial_api_request(registration_number, response_data)
    # The service expects an array response from the API
    stub_request(:get, "https://api.brreg.no/regnskapsregisteret/regnskap/#{registration_number}")
      .to_return(
        status: 200,
        body: [ {
          regnskapsperiode: { fraDato: "2023-01-01" },
          resultatregnskapResultat: {
            driftsresultat: {
              driftsinntekter: { sumDriftsinntekter: response_data[:revenue] }
            },
            aarsresultat: response_data[:profit]
          },
          egenkapitalGjeld: {
            egenkapital: { sumEgenkapital: response_data[:equity] },
            gjeldOversikt: {
              kortsiktigGjeld: { sumKortsiktigGjeld: response_data[:current_liabilities] },
              langsiktigGjeld: { sumLangsiktigGjeld: response_data[:long_term_liabilities] }
            }
          },
          eiendeler: {
            sumEiendeler: response_data[:total_assets],
            omloepsmidler: { sumOmloepsmidler: response_data[:current_assets] },
            anleggsmidler: { sumAnleggsmidler: response_data[:fixed_assets] }
          }
        } ].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_financial_api_rate_limit(registration_number)
    stub_request(:get, "https://api.brreg.no/regnskapsregisteret/regnskap/#{registration_number}")
      .to_return(
        status: 429,
        body: { error: 'Rate limit exceeded' }.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'Retry-After' => '60'
        }
      )
  end

  def stub_financial_api_error(registration_number, status_code)
    stub_request(:get, "https://api.brreg.no/regnskapsregisteret/regnskap/#{registration_number}")
      .to_return(
        status: status_code,
        body: { error: 'Internal server error' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def expect_no_financial_api_calls
    expect(WebMock).not_to have_requested(:get, /regnskapsregisteret/)
  end
end
