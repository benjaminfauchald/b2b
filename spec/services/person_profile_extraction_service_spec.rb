# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonProfileExtractionService, type: :service do
  let(:company) { create(:company, linkedin_url: 'https://linkedin.com/company/example') }
  let(:service) { described_class.new(company_id: company.id) }

  before do
    # Mock PhantomBuster configuration
    ENV['PHANTOMBUSTER_PHANTOM_ID'] = 'test_phantom_id'
    ENV['PHANTOMBUSTER_API_KEY'] = 'test_api_key'
  end

  after do
    ENV.delete('PHANTOMBUSTER_PHANTOM_ID')
    ENV.delete('PHANTOMBUSTER_API_KEY')
  end

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        ServiceConfiguration.find_or_create_by(service_name: 'person_profile_extraction') do |config|
          config.active = true
        end
      end

      context 'when company has LinkedIn URL' do
        context 'with successful PhantomBuster execution' do
          before do
            # Mock PhantomBuster API calls
            stub_phantombuster_config_fetch
            stub_phantombuster_config_save
            stub_phantombuster_launch
            stub_phantombuster_monitor_success
            stub_phantombuster_results
          end

          it 'creates a successful audit log' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('person_profile_extraction')
            expect(audit_log.operation_type).to eq('extract')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.execution_time_ms).to be_present
          end

          it 'includes metadata about the extraction' do
            result = service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['container_id']).to eq('test_container_123')
            expect(audit_log.metadata['phantom_id']).to eq('test_phantom_id')
            expect(audit_log.metadata['profiles_extracted']).to eq(3)
            expect(audit_log.metadata['json_url']).to be_present
          end

          it 'returns successful result with profile count' do
            result = service.perform

            expect(result.success?).to be true
            expect(result.message).to eq('Profile extraction completed')
            expect(result.data[:profiles_extracted]).to eq(3)
            expect(result.data[:container_id]).to eq('test_container_123')
          end

          it 'creates Person records in the database' do
            expect { service.perform }.to change(Person, :count).by(3)

            persons = Person.where(company: company)
            expect(persons.count).to eq(3)

            first_person = persons.first
            expect(first_person.name).to eq('John Doe')
            expect(first_person.title).to eq('Software Engineer')
            expect(first_person.phantom_run_id).to eq('test_container_123')
            expect(first_person.profile_extracted_at).to be_present
          end

          it 'tracks execution time in audit log' do
            start_time = Time.current
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.execution_time_ms).to be > 0
            expect(audit_log.started_at).to be_present
            expect(audit_log.completed_at).to be_present
          end
        end

        context 'with PhantomBuster execution failure' do
          before do
            stub_phantombuster_config_fetch
            stub_phantombuster_config_save
            stub_phantombuster_launch
            stub_phantombuster_monitor_failure
          end

          it 'creates audit log with failed status' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('person_profile_extraction')
            expect(audit_log.status).to eq('failed')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.error_message).to include('Profile extraction failed')
          end

          it 'returns error result' do
            result = service.perform

            expect(result.success?).to be false
            expect(result.error).to include('Profile extraction failed')
          end

          it 'does not create Person records' do
            expect { service.perform }.not_to change(Person, :count)
          end
        end

        context 'with PhantomBuster API error' do
          before do
            stub_phantombuster_config_fetch_error
          end

          it 'creates audit log with failed status' do
            expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('failed')
            expect(audit_log.error_message).to include('Failed to fetch phantom config')
          end

          it 'returns error result' do
            result = service.perform

            expect(result.success?).to be false
            expect(result.error).to include('Service error: Failed to fetch phantom config')
          end
        end
      end

      context 'when company has no LinkedIn URL' do
        let(:company) { create(:company, linkedin_url: nil) }

        it 'returns early without processing' do
          result = service.perform

          expect(result.success?).to be false
          expect(result.error).to eq('Company has no valid LinkedIn URL')
        end

        it 'does not create audit log for early return' do
          expect { service.perform }.not_to change(ServiceAuditLog, :count)
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        create(:service_configuration, service_name: 'person_profile_extraction', active: false)
      end

      it 'does not perform extraction' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to eq('Service is disabled')
      end

      it 'does not create audit log' do
        expect { service.perform }.not_to change(ServiceAuditLog, :count)
      end
    end

    context 'when PhantomBuster is not configured' do
      before do
        ENV.delete('PHANTOMBUSTER_PHANTOM_ID')
        ServiceConfiguration.find_or_create_by(service_name: 'person_profile_extraction') do |config|
          config.active = true
        end
      end

      it 'returns configuration error' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.error).to eq('Missing PhantomBuster configuration')
      end
    end
  end

  private

  def stub_phantombuster_config_fetch
    stub_request(:get, "https://api.phantombuster.com/api/v2/agents/fetch?id=test_phantom_id")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => 'test_api_key'
        }
      )
      .to_return(
        status: 200,
        body: {
          argument: '{"spreadsheetUrl": "old_url"}'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_config_save
    stub_request(:post, "https://api.phantombuster.com/api/v2/agents/save")
      .to_return(status: 200, body: '{}')
  end

  def stub_phantombuster_launch
    stub_request(:post, "https://api.phantombuster.com/api/v2/agents/launch")
      .to_return(
        status: 200,
        body: { containerId: 'test_container_123' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_monitor_success
    stub_request(:get, "https://api.phantombuster.com/api/v2/containers/fetch")
      .with(query: { id: 'test_container_123' })
      .to_return(
        status: 200,
        body: { status: 'success' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:get, "https://api.phantombuster.com/api/v2/containers/fetch-output")
      .with(query: { id: 'test_container_123' })
      .to_return(
        status: 200,
        body: {
          output: 'JSON saved at https://example.com/results.json'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_monitor_failure
    stub_request(:get, "https://api.phantombuster.com/api/v2/containers/fetch")
      .with(query: { id: 'test_container_123' })
      .to_return(
        status: 200,
        body: { status: 'failed' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_config_fetch_error
    stub_request(:get, "https://api.phantombuster.com/api/v2/agents/fetch?id=test_phantom_id")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => 'test_api_key'
        }
      )
      .to_return(status: 500, body: 'Internal Server Error')
  end

  def stub_phantombuster_results
    stub_request(:get, "https://example.com/results.json")
      .to_return(
        status: 200,
        body: [
          {
            'fullName' => 'John Doe',
            'title' => 'Software Engineer',
            'location' => 'San Francisco',
            'linkedInProfileUrl' => 'https://linkedin.com/in/johndoe',
            'email' => 'john@example.com',
            'connectionDegree' => '2nd'
          },
          {
            'fullName' => 'Jane Smith',
            'title' => 'Product Manager',
            'location' => 'New York',
            'linkedInProfileUrl' => 'https://linkedin.com/in/janesmith',
            'email' => 'jane@example.com',
            'connectionDegree' => '1st'
          },
          {
            'fullName' => 'Bob Wilson',
            'title' => 'Designer',
            'location' => 'Austin',
            'linkedInProfileUrl' => 'https://linkedin.com/in/bobwilson',
            'email' => 'bob@example.com',
            'connectionDegree' => '3rd'
          }
        ].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end
