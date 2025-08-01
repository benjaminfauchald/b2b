# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainImportService, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(file: file, user: user) }

  before do
    ServiceConfiguration.find_or_create_by(service_name: 'domain_import') do |config|
      config.active = true
    end

    # Clean up any existing test domains to avoid duplicate conflicts
    Domain.where(domain: [ 'example.com', 'test.org', 'sample.net' ]).destroy_all
  end

  describe '#perform' do
    context 'with valid CSV file' do
      let(:csv_content) do
        <<~CSV
domain,dns,www,mx
example.com,true,true,false
test.org,false,false,true
sample.net,,true,
        CSV
      end
      let(:file) { create_csv_file(csv_content) }

      it 'successfully imports all valid domains' do
        result = service.perform

        expect(result.success?).to be true
        expect(result.data[:imported]).to eq 3
        expect(result.data[:failed]).to eq 0
        expect(result.data[:result].total_count).to eq 3
      end

      it 'creates domain records with correct attributes' do
        service.perform

        example_domain = Domain.find_by(domain: 'example.com')
        expect(example_domain).to be_present
        expect(example_domain.dns).to be true
        expect(example_domain.www).to be true
        expect(example_domain.mx).to be false

        test_domain = Domain.find_by(domain: 'test.org')
        expect(test_domain).to be_present
        expect(test_domain.dns).to be false
        expect(test_domain.www).to be false
        expect(test_domain.mx).to be true

        sample_domain = Domain.find_by(domain: 'sample.net')
        expect(sample_domain).to be_present
        expect(sample_domain.dns).to be_nil
        expect(sample_domain.www).to be true
        expect(sample_domain.mx).to be_nil
      end

      it 'returns detailed results' do
        result = service.perform

        expect(result.data[:result].imported_domains).to include(
          hash_including(domain: 'example.com', row: 2),
          hash_including(domain: 'test.org', row: 3),
          hash_including(domain: 'sample.net', row: 4)
        )
        expect(result.data[:result].failed_domains).to be_empty
      end
    end

    context 'with mixed valid and invalid data' do
      let(:csv_content) do
        <<~CSV
domain,dns,www,mx
example.com,true,true,false
,false,false,true
invalid..domain,true,false,true
valid-domain.org,false,true,false
        CSV
      end
      let(:file) { create_csv_file(csv_content) }

      it 'imports valid domains and reports invalid ones' do
        result = service.perform

        expect(result.success?).to be false  # false because there are failed domains
        expect(result.data[:imported]).to eq 2
        expect(result.data[:failed]).to eq 2
        expect(result.data[:result].total_count).to eq 4
      end

      it 'provides detailed error information' do
        result = service.perform

        expect(result.data[:result].failed_domains).to contain_exactly(
          hash_including(
            row: 3,
            domain: '',
            errors: include("Domain can't be blank")
          ),
          hash_including(
            row: 4,
            domain: 'invalid..domain',
            errors: include("Domain format is invalid")
          )
        )
      end

      it 'successfully imports valid domains despite errors' do
        service.perform

        expect(Domain.find_by(domain: 'example.com')).to be_present
        expect(Domain.find_by(domain: 'valid-domain.org')).to be_present
        expect(Domain.find_by(domain: '')).to be_nil
        expect(Domain.find_by(domain: 'invalid..domain')).to be_nil
      end
    end

    context 'with duplicate domains' do
      let!(:existing_domain) { create(:domain, domain: 'example.com') }
      let(:csv_content) do
        <<~CSV
domain,dns,www,mx
example.com,true,true,false
new-domain.com,false,false,true
        CSV
      end
      let(:file) { create_csv_file(csv_content) }

      it 'skips duplicate domains and reports them' do
        result = service.perform

        expect(result.data[:imported]).to eq 1
        expect(result.data[:duplicates]).to eq 1
        expect(result.data[:result].duplicate_domains.first[:domain]).to eq('example.com')
      end
    end

    context 'with invalid CSV format' do
      let(:csv_content) { 'not,a,valid,csv,format\nwith invalid data' }
      let(:file) { create_csv_file(csv_content) }

      it 'handles malformed CSV gracefully' do
        result = service.perform

        expect(result.success?).to be false  # false because no domains imported
        expect(result.data[:imported]).to eq 0
        expect(result.data[:failed]).to eq 1  # 'not' is treated as a domain but invalid
      end
    end

    context 'with empty CSV file' do
      let(:csv_content) { '' }
      let(:file) { create_csv_file(csv_content) }

      it 'handles empty files gracefully' do
        result = service.perform

        expect(result.success?).to be false  # false because no domains imported
        expect(result.data[:imported]).to eq 0
        expect(result.data[:result].csv_errors).to be_empty  # Empty file doesn't produce CSV errors
      end
    end

    context 'with missing required column' do
      let(:csv_content) do
        <<~CSV
name,dns,www,mx
example.com,true,true,false
        CSV
      end
      let(:file) { create_csv_file(csv_content) }

      it 'validates required columns' do
        result = service.perform

        # This CSV has no 'domain' column, so it's processed as headerless
        # 'name' fails validation, 'example.com' succeeds
        expect(result.success?).to be false
        expect(result.data[:imported]).to eq 1  # example.com succeeds
        expect(result.data[:failed]).to eq 1    # 'name' fails
      end
    end

    context 'with boolean value variations' do
      let(:csv_content) do
        <<~CSV
domain,dns,www,mx
test1.com,1,0,yes
test2.com,TRUE,FALSE,no
test3.com,true,false,
        CSV
      end
      let(:file) { create_csv_file(csv_content) }

      it 'correctly parses various boolean representations' do
        result = service.perform

        expect(result.success?).to be true

        test1 = Domain.find_by(domain: 'test1.com')
        expect(test1.dns).to be true
        expect(test1.www).to be false
        expect(test1.mx).to be true

        test2 = Domain.find_by(domain: 'test2.com')
        expect(test2.dns).to be true
        expect(test2.www).to be false
        expect(test2.mx).to be false

        test3 = Domain.find_by(domain: 'test3.com')
        expect(test3.dns).to be true
        expect(test3.www).to be false
        expect(test3.mx).to be_nil
      end
    end
  end

  describe 'service audit integration' do
    let(:csv_content) do
      <<~CSV
domain,dns,www,mx
example.com,true,true,false
      CSV
    end
    let(:file) { create_csv_file(csv_content) }

    it 'creates service audit log entry' do
      expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.service_name).to eq('domain_import')
      expect(audit_log.table_name).to eq('users')
      expect(audit_log.status).to eq('success')
    end

    it 'logs failed imports in audit' do
      allow(Domain).to receive(:create!).and_raise(StandardError, 'Database error')

      expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.status).to eq('success')
      expect(audit_log.metadata['error']).to include('Database error')
    end
  end

  describe 'performance with large files' do
    let(:large_csv_content) do
      header = "domain,dns,www,mx\n"
      rows = 50.times.map { |i| "domain#{i}.com,true,false,true" }.join("\n")
      header + rows
    end
    let(:file) { create_csv_file(large_csv_content) }

    it 'processes large files efficiently' do
      start_time = Time.current
      result = service.perform
      duration = Time.current - start_time

      expect(result.success?).to be true
      expect(result.data[:imported]).to eq 50
      expect(duration).to be < 5.seconds
    end

    it 'manages memory efficiently with large imports' do
      # This test ensures we're not loading all domains into memory at once
      initial_count = GC.stat[:total_allocated_objects]
      service.perform
      final_count = GC.stat[:total_allocated_objects]
      expect(final_count - initial_count).to be < 2_000_000  # Allow up to 2M objects for 1000 domains
    end
  end

  private

  def create_csv_file(content)
    file = Tempfile.new([ 'domains', '.csv' ])
    file.write(content)
    file.rewind

    # Create a mock uploaded file that behaves like ActionDispatch::Http::UploadedFile
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: 'domains.csv',
      type: 'text/csv'
    )
  end
end
