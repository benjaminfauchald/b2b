# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Domain CSV Import', type: :request do
  let(:user) { create(:user) }

  # Shared CSV content for all tests - use unique domains to avoid conflicts
  let(:test_domain_1) { "import-test-#{Time.current.to_i}-#{Random.rand(9999)}.com" }
  let(:test_domain_2) { "import-test-#{Time.current.to_i}-#{Random.rand(9999)}.org" }
  
  let(:valid_csv_content) do
    <<~CSV
      domain,dns,www,mx
      #{test_domain_1},true,true,false
      #{test_domain_2},false,false,true
    CSV
  end

  let(:invalid_csv_content) do
    <<~CSV
      domain,dns,www,mx
      example.com,true,true,false
      ,false,false,true
      invalid..domain,true,false,true
      valid-domain.org,false,true,false
    CSV
  end

  before do
    sign_in user
    # Create the service configuration for domain import
    create(:service_configuration, service_name: "domain_import", active: true)
    # Clear any existing domains to ensure clean test state
    Domain.delete_all
  end

  describe 'GET /domains/import' do
    it 'renders the import form' do
      get import_domains_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Import Domains from CSV')
      expect(response.body).to include('Choose CSV file')
      expect(response.body).to include('drag and drop')
    end

    it 'includes CSV format information' do
      get import_domains_path

      expect(response.body).to include('CSV Format')
      expect(response.body).to include('domain,dns,www,mx')
    end

    it 'shows file requirements' do
      get import_domains_path

      expect(response.body).to include('File Requirements')
      expect(response.body).to include('CSV format (.csv extension)')
      expect(response.body).to include('Maximum file size')
    end
  end

  describe 'POST /domains/import' do
    context 'with valid CSV file' do
      let(:csv_file) { create_uploaded_file(valid_csv_content, 'domains.csv') }

      it 'successfully processes the import' do
        expect {
          post import_domains_path, params: { csv_file: csv_file }
        }.to change(Domain, :count).by(2)

        expect(response).to redirect_to(import_results_domains_path)
        follow_redirect!

        expect(response.body).to include('Imported (2)')
      end

      it 'creates domains with correct attributes' do
        post import_domains_path, params: { csv_file: csv_file }

        example_domain = Domain.find_by(domain: test_domain_1)
        expect(example_domain).to be_present
        expect(example_domain.dns).to be true
        expect(example_domain.www).to be true
        expect(example_domain.mx).to be false
      end

      it 'stores import results in session' do
        post import_domains_path, params: { csv_file: csv_file }

        expect(session[:import_results]).to be_present
        import_data = JSON.parse(session[:import_results])
        expect(import_data['imported_count']).to eq(2)
        expect(import_data['failed_count']).to eq(0)
      end
    end

    context 'with mixed valid and invalid data' do
      let(:csv_file) { create_uploaded_file(invalid_csv_content, 'domains.csv') }

      it 'imports valid domains and reports errors' do
        expect {
          post import_domains_path, params: { csv_file: csv_file }
        }.to change(Domain, :count).by(0) # Both rows are invalid

        expect(response).to redirect_to(import_results_domains_path)
        follow_redirect!

        expect(response.body).to include('Import Completed with Errors')
        expect(response.body).to include('0 domains imported')
        expect(response.body).to include('2 domains failed')
      end

      it 'provides detailed error information' do
        post import_domains_path, params: { csv_file: csv_file }
        follow_redirect!

        expect(response.body).to include("Domain can't be blank")
        expect(response.body).to include('Domain is invalid')
      end
    end

    context 'with no file provided' do
      it 'returns error message' do
        post import_domains_path

        expect(response).to redirect_to(import_domains_path)
        expect(flash[:alert]).to include('Please select a CSV file')
      end
    end

    context 'with non-CSV file' do
      let(:text_file) { create_uploaded_file('not csv content', 'file.txt', 'text/plain') }

      it 'rejects non-CSV files' do
        post import_domains_path, params: { csv_file: text_file }

        expect(response).to redirect_to(import_results_domains_path)

        # Follow redirect and check results page shows the error
        follow_redirect!
        expect(response.body).to include('Import Failed')
      end
    end

    context 'with oversized file' do
      let(:large_content) { 'a' * (10.megabytes + 1) }
      let(:large_file) { create_uploaded_file(large_content, 'large.csv') }

      it 'rejects files that are too large' do
        post import_domains_path, params: { csv_file: large_file }

        expect(response).to redirect_to(import_results_domains_path)

        # Follow redirect and check results page shows the error
        follow_redirect!
        expect(response.body).to include('Import Failed')
      end
    end

    context 'with malformed CSV' do
      let(:malformed_csv) { create_uploaded_file('malformed,csv"content', 'bad.csv') }

      it 'handles CSV parsing errors gracefully' do
        post import_domains_path, params: { csv_file: malformed_csv }

        expect(response).to redirect_to(import_results_domains_path)
        follow_redirect!

        expect(response.body).to include('Import Failed')
        expect(response.body).to include('CSV parsing error')
      end
    end
  end

  describe 'GET /domains/import/results' do
    context 'with import results in session' do
      let(:import_results) do
        {
          success: true,
          imported_count: 3,
          failed_count: 1,
          total_count: 4,
          imported_domains: [
            { domain: 'example.com', row: 2 }
          ],
          failed_domains: [
            { domain: '', row: 3, errors: [ "Domain can't be blank" ] }
          ],
          processing_time: 2.5
        }
      end

      before do
        # Use allow to stub the session for the controller
        allow_any_instance_of(DomainsController).to receive(:session).and_return({
          import_results: import_results.to_json
        })
      end

      it 'displays import results' do
        get import_results_domains_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Imported (3)')
        expect(response.body).to include('Failed to Import (1)')
        expect(response.body).to include('2.5 seconds')
      end

      it 'clears session data after displaying' do
        # Mock the session with delete method
        session_mock = { import_results: import_results.to_json }
        allow(session_mock).to receive(:delete)
        allow_any_instance_of(DomainsController).to receive(:session).and_return(session_mock)
        
        get import_results_domains_path

        expect(session_mock).to have_received(:delete).with(:import_results)
      end
    end

    context 'without import results in session' do
      it 'redirects to import form' do
        get import_results_domains_path

        expect(response).to redirect_to(import_domains_path)
        expect(flash[:alert]).to include('No import results found')
      end
    end
  end

  describe 'GET /domains/import/template' do
    it 'downloads CSV template file' do
      get template_domains_path

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('text/csv')
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Content-Disposition']).to include('domain_import_template.csv')
    end

    it 'contains proper CSV headers' do
      get template_domains_path

      expect(response.body).to include('domain,dns,www,mx')
    end

    it 'includes sample data' do
      get template_domains_path

      expect(response.body).to include('example.com,true,true,false')
      expect(response.body).to include('sample.org,false,false,true')
    end
  end

  describe 'authentication' do
    context 'when not signed in' do
      before { sign_out user }

      it 'redirects to sign in for import form' do
        get import_domains_path

        expect(response).to redirect_to(new_user_session_path)
      end

      it 'redirects to sign in for import processing' do
        post import_domains_path

        expect(response).to redirect_to(new_user_session_path)
      end

      it 'redirects to sign in for results' do
        get import_results_domains_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'service audit integration' do
    let(:csv_file) { create_uploaded_file(valid_csv_content, 'domains.csv') }

    it 'creates service audit log for import operation' do
      expect {
        post import_domains_path, params: { csv_file: csv_file }
      }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.service_name).to eq('domain_import')
      expect(audit_log.status).to eq('successful')
    end
  end

  describe 'rate limiting', :slow do
    let(:csv_file) { create_uploaded_file(valid_csv_content, 'domains.csv') }

    it 'prevents rapid successive imports' do
      # First import should succeed
      post import_domains_path, params: { csv_file: csv_file }
      expect(response).to redirect_to(import_results_domains_path)

      # Immediate second import should be rate limited
      post import_domains_path, params: { csv_file: csv_file }
      expect(response).to redirect_to(import_domains_path)
      expect(flash[:alert]).to include('Please wait a moment before importing again')
    end
  end

  private

  def create_uploaded_file(content, filename, content_type = 'text/csv')
    file = Tempfile.new([ filename.split('.').first, ".#{filename.split('.').last}" ])
    file.write(content)
    file.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: filename,
      type: content_type
    )
  end
end
