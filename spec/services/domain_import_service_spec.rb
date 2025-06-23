# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainImportService, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(file: file, user: user) }

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
        expect(result.imported_count).to eq 3
        expect(result.failed_count).to eq 0
        expect(result.total_count).to eq 3
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

        expect(result.imported_domains).to include(
          hash_including(domain: 'example.com', row: 2),
          hash_including(domain: 'test.org', row: 3),
          hash_including(domain: 'sample.net', row: 4)
        )
        expect(result.failed_domains).to be_empty
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

        expect(result.success?).to be false
        expect(result.imported_count).to eq 2
        expect(result.failed_count).to eq 2
        expect(result.total_count).to eq 4
      end

      it 'provides detailed error information' do
        result = service.perform

        expect(result.failed_domains).to contain_exactly(
          hash_including(
            row: 3,
            domain: '',
            errors: include("Domain can't be blank")
          ),
          hash_including(
            row: 4,
            domain: 'invalid..domain',
            errors: include(match(/Domain is invalid/))
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

        expect(result.imported_count).to eq 1
        expect(result.failed_count).to eq 1
        expect(result.failed_domains.first[:errors]).to include('Domain has already been taken')
      end
    end

    context 'with invalid CSV format' do
      let(:csv_content) { 'not,a,valid,csv,format\nwith invalid data' }
      let(:file) { create_csv_file(csv_content) }

      it 'handles malformed CSV gracefully' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.imported_count).to eq 0
        expect(result.has_csv_errors?).to be true
      end
    end

    context 'with empty CSV file' do
      let(:csv_content) { '' }
      let(:file) { create_csv_file(csv_content) }

      it 'handles empty files gracefully' do
        result = service.perform

        expect(result.success?).to be false
        expect(result.imported_count).to eq 0
        expect(result.error_message).to include('CSV file is empty')
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

        expect(result.success?).to be false
        expect(result.error_message).to include('Missing required column: domain')
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
      expect(audit_log.table_name).to eq('domains')
      expect(audit_log.status).to eq('successful')
    end

    it 'logs failed imports in audit' do
      allow(Domain).to receive(:create!).and_raise(StandardError, 'Database error')

      expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

      audit_log = ServiceAuditLog.last
      expect(audit_log.status).to eq('failed')
      expect(audit_log.error_message).to include('Database error')
    end
  end

  describe 'performance with large files' do
    let(:large_csv_content) do
      header = "domain,dns,www,mx\n"
      rows = 1000.times.map { |i| "domain#{i}.com,true,false,true" }.join("\n")
      header + rows
    end
    let(:file) { create_csv_file(large_csv_content) }

    it 'processes large files efficiently' do
      start_time = Time.current
      result = service.perform
      duration = Time.current - start_time

      expect(result.success?).to be true
      expect(result.imported_count).to eq 1000
      expect(duration).to be < 30.seconds
    end

    it 'manages memory efficiently with large imports' do
      # This test ensures we're not loading all domains into memory at once
      expect { service.perform }.not_to change {
        GC.stat[:total_allocated_objects]
      }.by_more_than(50_000)
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
