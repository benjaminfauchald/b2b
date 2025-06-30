require 'rails_helper'

RSpec.describe CompanyEmployeeDiscoveryService do
  let(:company) { create(:company, registration_number: '123456789', company_name: 'Test Company AS') }
  let(:service) { described_class.new(company) }

  before do
    # Set up environment variables for test APIs
    stub_const('ENV', ENV.to_h.merge(
      'LINKEDIN_API_ENDPOINT' => 'http://linkedin',
      'WEB_SCRAPER_API' => 'http://scrape',
      'BRREG_API_ENDPOINT' => 'http://brreg'
    ))
  end

  describe '#perform' do
    context 'when service configuration is active' do
      before do
        config = ServiceConfiguration.find_or_create_by(service_name: 'company_employee_discovery')
        config.update!(
          active: true,
          refresh_interval_hours: 1080, # 45 days
          settings: {
            sources: [ 'linkedin', 'company_websites', 'public_registries' ],
            max_employees_to_discover: 100
          }
        )
      end

      context 'when company needs employee discovery' do
        before do
          allow(company).to receive(:needs_service?).with('company_employee_discovery').and_return(true)
        end

        context 'with successful employee discovery' do
          let(:discovered_employees) do
            {
              total_found: 25,
              by_source: {
                linkedin: 15,
                company_websites: 8,
                public_registries: 2
              },
              employees: [
                {
                  name: 'John Doe',
                  title: 'CEO',
                  email: 'john.doe@testcompany.no',
                  linkedin_url: 'https://linkedin.com/in/johndoe',
                  source: 'linkedin',
                  confidence: 0.95
                },
                {
                  name: 'Jane Smith',
                  title: 'CTO',
                  email: 'jane.smith@testcompany.no',
                  linkedin_url: 'https://linkedin.com/in/janesmith',
                  source: 'linkedin',
                  confidence: 0.92
                },
                {
                  name: 'Ole Hansen',
                  title: 'CFO',
                  email: nil,
                  linkedin_url: nil,
                  source: 'public_registries',
                  confidence: 1.0
                }
              ],
              key_contacts: {
                ceo: 'John Doe',
                cto: 'Jane Smith',
                cfo: 'Ole Hansen'
              }
            }
          end

          before do
            stub_employee_discovery_apis(company, discovered_employees)
          end

          it 'discovers and stores employee information' do
            result = service.perform

            expect(result).to be_success
            
            # Check the data structure and totals
            discovered_data = result.data[:discovered_employees]
            expect(discovered_data[:total_found]).to eq(25)
            expect(discovered_data[:by_source]).to eq({
              'linkedin' => 15,
              'company_websites' => 8,
              'public_registries' => 2
            })
            
            # Check that key employees from test data are present
            employees = discovered_data[:employees]
            expect(employees.find { |e| e[:name] == 'John Doe' && e[:title] == 'CEO' }).to be_present
            expect(employees.find { |e| e[:name] == 'Jane Smith' && e[:title] == 'CTO' }).to be_present
            expect(employees.find { |e| e[:name] == 'Ole Hansen' && e[:title] == 'CFO' }).to be_present

            company.reload
            expect(company.employees_data).to be_present
            employees_data = JSON.parse(company.employees_data)
            expect(employees_data['total_found']).to eq(25)
          end

          it 'creates a successful audit log' do
            expect {
              service.perform
            }.to change(ServiceAuditLog, :count).by(1)

            audit_log = ServiceAuditLog.last
            expect(audit_log.service_name).to eq('company_employee_discovery')
            expect(audit_log.status).to eq('success')
            expect(audit_log.auditable).to eq(company)
            expect(audit_log.metadata['employees_found']).to eq(25)
            expect(audit_log.metadata['sources_used']).to eq([ 'linkedin', 'company_websites', 'public_registries' ])
          end

          it 'updates employee_discovery_updated_at timestamp' do
            freeze_time do
              service.perform
              expect(company.reload.employee_discovery_updated_at).to eq(Time.current)
            end
          end

          it 'identifies key contacts' do
            service.perform

            company.reload
            employees_data = JSON.parse(company.employees_data)
            expect(employees_data['key_contacts']['ceo']).to eq('John Doe')
            expect(employees_data['key_contacts']['cto']).to eq('Jane Smith')
          end

          it 'tracks discovery sources' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['by_source']).to eq({
              'linkedin' => 15,
              'company_websites' => 8,
              'public_registries' => 2
            })
          end
        end

        context 'with partial source failures' do
          let(:partial_results) do
            {
              total_found: 10,
              by_source: {
                linkedin: 0, # Failed
                company_websites: 8,
                public_registries: 2
              },
              employees: [],
              errors: {
                linkedin: 'API temporarily unavailable'
              }
            }
          end

          before do
            stub_employee_discovery_with_partial_failure(company, partial_results)
          end

          it 'continues with available sources' do
            result = service.perform

            expect(result).to be_success
            expect(result.message).to include('Partial success')

            company.reload
            employees_data = JSON.parse(company.employees_data)
            expect(employees_data['total_found']).to eq(10)
          end

          it 'logs partial failures in audit' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.metadata['partial_failures']).to include('linkedin')
            expect(audit_log.metadata['errors']['linkedin']).to eq('API temporarily unavailable')
          end
        end

        context 'when no employees found' do
          before do
            stub_employee_discovery_apis(company, { total_found: 0, employees: [] })
          end

          it 'handles empty results gracefully' do
            result = service.perform

            expect(result).to be_success
            expect(result.message).to include('No employees found')

            company.reload
            employees_data = JSON.parse(company.employees_data)
            expect(employees_data['total_found']).to eq(0)
          end
        end

        context 'with rate limiting on multiple sources' do
          before do
            stub_employee_discovery_rate_limited(company)
          end

          it 'handles rate limits across sources' do
            result = service.perform

            expect(result).not_to be_success
            expect(result.error).to include('rate limit')
            expect(result.retry_after).to be_present
          end

          it 'creates audit log with rate_limited status' do
            service.perform

            audit_log = ServiceAuditLog.last
            expect(audit_log.status).to eq('rate_limited')
            expect(audit_log.metadata['rate_limited']).to be true
            expect(audit_log.metadata['retry_after']).to eq(3600)
          end
        end

        context 'with email validation' do
          let(:employees_with_emails) do
            {
              total_found: 3,
              employees: [
                { name: 'Valid Email', email: 'valid@testcompany.no' },
                { name: 'Invalid Email', email: 'not-an-email' },
                { name: 'No Email', email: nil }
              ]
            }
          end

          before do
            stub_employee_discovery_apis(company, employees_with_emails)
          end

          it 'validates and filters email addresses' do
            service.perform

            company.reload
            employees_data = JSON.parse(company.employees_data)
            valid_employees = employees_data['employees'].select { |e| e['email_valid'] }
            expect(valid_employees.count).to eq(1)
          end
        end

        context 'with duplicate detection' do
          let(:employees_with_duplicates) do
            {
              # LinkedIn will return John Doe and Jane Smith
              # Company websites will return John Doe (duplicate)
              # After deduplication: John Doe, Jane Smith (2 unique)
              linkedin_employees: [
                { name: 'John Doe', source: 'linkedin' },
                { name: 'Jane Smith', source: 'linkedin' }
              ],
              website_employees: [
                { name: 'John Doe', source: 'company_websites' }
              ]
            }
          end

          before do
            # LinkedIn API
            stub_request(:get, "http://linkedin/company/#{company.registration_number}/employees")
              .to_return(
                status: 200,
                body: { employees: employees_with_duplicates[:linkedin_employees] }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

            # Company website scraping
            stub_request(:get, "http://scrape/scrape")
              .with(query: hash_including(url: company.website))
              .to_return(
                status: 200,
                body: { employees: employees_with_duplicates[:website_employees] }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

            # Public registry API (no employees)
            stub_request(:get, "http://brreg/roller/#{company.registration_number}")
              .to_return(
                status: 200,
                body: { board_members: [] }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )
          end

          it 'deduplicates employees across sources' do
            service.perform

            company.reload
            employees_data = JSON.parse(company.employees_data)
            unique_names = employees_data['employees'].map { |e| e['name'] }.uniq
            expect(unique_names.count).to eq(2)
          end
        end
      end

      context 'when company does not need update' do
        before do
          allow(company).to receive(:needs_service?).with('company_employee_discovery').and_return(false)
        end

        it 'returns early without making API calls' do
          expect_no_employee_discovery_api_calls

          result = service.perform

          expect(result).to be_success
          expect(result.message).to eq('Employee discovery data is up to date')
        end

        it 'creates audit log with skipped status' do
          service.perform

          audit_log = ServiceAuditLog.last
          expect(audit_log.status).to eq('success')
          expect(audit_log.metadata['skipped']).to be true
          expect(audit_log.metadata['reason']).to eq('up_to_date')
        end
      end

      context 'with source configuration' do
        before do
          config = ServiceConfiguration.find_or_create_by(service_name: 'company_employee_discovery')
          config.update!(
            active: true,
            settings: {
              sources: [ 'linkedin' ], # Only use LinkedIn
              max_employees_to_discover: 10
            }
          )
        end

        it 'respects configured sources' do
          stub_employee_discovery_apis(company, { total_found: 5, by_source: { linkedin: 5 } })

          result = service.perform

          expect(result).to be_success
          audit_log = ServiceAuditLog.last
          expect(audit_log.metadata['sources_used']).to eq([ 'linkedin' ])
        end
      end
    end

    context 'when service configuration is inactive' do
      before do
        ServiceConfiguration.find_or_create_by(service_name: 'company_employee_discovery') do |config|
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
    before do
      # Create service configuration
      ServiceConfiguration.find_or_create_by(service_name: 'company_employee_discovery') do |config|
        config.active = true
        config.refresh_interval_hours = 1080 # 45 days
      end
    end

    context 'when employee data is missing' do
      before do
        company.update!(employees_data: nil)
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when employee discovery is stale' do
      before do
        company.update!(
          employee_discovery_updated_at: 46.days.ago,
          employees_data: { total_found: 10, employees: [] }.to_json
        )
      end

      it 'returns true' do
        expect(service.send(:needs_update?)).to be true
      end
    end

    context 'when employee discovery is recent' do
      before do
        company.update!(
          employee_discovery_updated_at: 1.day.ago,
          employees_data: { total_found: 25, employees: [] }.to_json
        )
        
        # Create a successful audit log from 1 day ago
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'company_employee_discovery',
          operation_type: 'process',
          status: :success,
          table_name: 'companies',
          record_id: company.id.to_s,
          columns_affected: ['employees_data'],
          metadata: { employees_found: 25 },
          started_at: 1.day.ago,
          completed_at: 1.day.ago
        )
      end

      it 'returns false' do
        expect(service.send(:needs_update?)).to be false
      end
    end

    context 'when company has grown significantly' do
      before do
        company.update!(
          employee_discovery_updated_at: 30.days.ago,
          employees_data: { total_found: 10, employees: [] }.to_json,
          employee_count: 100 # Official count is much higher
        )
        
        # Create a successful audit log from 30 days ago (within 45 day window)
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'company_employee_discovery',
          operation_type: 'process',
          status: :success,
          table_name: 'companies',
          record_id: company.id.to_s,
          columns_affected: ['employees_data'],
          metadata: { employees_found: 10 },
          started_at: 30.days.ago,
          completed_at: 30.days.ago
        )
      end

      it 'could trigger update based on growth' do
        # This could be enhanced to detect significant company changes
        expect(service.send(:needs_update?)).to be false # Still within 45 day window
      end
    end
  end

  # Helper methods for stubbing API requests
  def stub_employee_discovery_apis(company, response_data)
    # Get expected counts from by_source data or fall back to distributing employees
    if response_data[:by_source]
      linkedin_count = response_data[:by_source]&.fetch(:linkedin, 0) || 0
      website_count = response_data[:by_source]&.fetch(:company_websites, 0) || 0
      registry_count = response_data[:by_source]&.fetch(:public_registries, 0) || 0
    else
      # Distribute employees across sources for tests without by_source data
      total_employees = response_data[:employees]&.count || response_data[:total_found] || 0
      linkedin_count = total_employees
      website_count = 0
      registry_count = 0
    end
    
    # Separate employees by source from test data
    linkedin_employees = response_data[:employees]&.select { |e| e[:source] == 'linkedin' } || []
    website_employees = response_data[:employees]&.select { |e| e[:source] == 'company_websites' } || []
    registry_employees = response_data[:employees]&.select { |e| e[:source] == 'public_registries' } || []
    
    # If no employees have sources assigned, assign them all to LinkedIn
    if linkedin_employees.empty? && registry_employees.empty? && website_employees.empty? && response_data[:employees]
      linkedin_employees = response_data[:employees].map { |emp| emp.merge(source: 'linkedin') }
    end
    
    # For deduplication tests, don't generate extra employees - use exactly what's provided
    # Generate additional employees to match expected counts only if needed
    while linkedin_employees.count < linkedin_count && linkedin_count > response_data[:employees]&.count.to_i
      index = linkedin_employees.count + 1
      linkedin_employees << {
        name: "LinkedIn Employee #{index}",
        title: "Professional",
        email: "employee#{index}@testcompany.no",
        linkedin_url: "https://linkedin.com/in/employee#{index}",
        source: "linkedin",
        confidence: 0.85
      }
    end

    # LinkedIn API
    stub_request(:get, "http://linkedin/company/#{company.registration_number}/employees")
      .to_return(
        status: 200,
        body: { employees: linkedin_employees }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Company website scraping (simulated)
    if company.website.present?
      # Generate mock website employees 
      website_employees = []
      if website_count > 0
        website_employees = (1..website_count).map do |i|
          {
            name: "Website Employee #{i}",
            title: "Staff Member",
            source: "company_websites",
            confidence: 0.8
          }
        end
      end

      stub_request(:get, "http://scrape/scrape")
        .with(query: hash_including(url: company.website))
        .to_return(
          status: 200,
          body: { employees: website_employees }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    # Public registry API
    # Convert registry employees to board_members format for API response
    board_members = registry_employees.map do |emp|
      {
        name: emp[:name],
        role: emp[:title],
        title: emp[:title]
      }
    end

    # Add more board members if count specified
    while board_members.count < registry_count
      index = board_members.count + 1
      board_members << {
        name: "Board Member #{index}",
        role: "Director",
        title: "Director"
      }
    end

    stub_request(:get, "http://brreg/roller/#{company.registration_number}")
      .to_return(
        status: 200,
        body: { board_members: board_members }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_employee_discovery_with_partial_failure(company, partial_results)
    # LinkedIn fails
    stub_request(:get, "http://linkedin/company/#{company.registration_number}/employees")
      .to_return(status: 503)

    # Other sources succeed with partial results
    website_count = partial_results[:by_source][:company_websites] || 0
    registry_count = partial_results[:by_source][:public_registries] || 0

    # Website scraping succeeds
    if company.website.present?
      website_employees = (1..website_count).map do |i|
        {
          name: "Website Employee #{i}",
          title: "Staff Member",
          source: "company_websites",
          confidence: 0.8
        }
      end

      stub_request(:get, "http://scrape/scrape")
        .with(query: hash_including(url: company.website))
        .to_return(
          status: 200,
          body: { employees: website_employees }.to_json
        )
    end

    # Registry succeeds 
    board_members = (1..registry_count).map do |i|
      {
        name: "Board Member #{i}",
        role: "Director",
        title: "Director"
      }
    end

    stub_request(:get, "http://brreg/roller/#{company.registration_number}")
      .to_return(
        status: 200,
        body: { board_members: board_members }.to_json
      )
  end

  def stub_employee_discovery_rate_limited(company)
    # LinkedIn API returns rate limit
    stub_request(:get, "http://linkedin/company/#{company.registration_number}/employees")
      .to_return(
        status: 429,
        headers: { 'Retry-After' => '3600' }
      )
    
    # Don't stub other services since the service should stop on rate limit
  end

  def expect_no_employee_discovery_api_calls
    expect(WebMock).not_to have_requested(:get, /employees|roller|scrape/)
  end
end
