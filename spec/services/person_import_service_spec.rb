# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonImportService, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(file: csv_file, user: user) }

  before do
    # Create service configuration
    ServiceConfiguration.create!(
      service_name: 'person_import',
      active: true
    )
  end

  describe '#perform' do
    context 'with valid CSV file' do
      let(:csv_content) do
        "Name,Email,Title,Company Name,Location,Linkedin\n" \
        "John Doe,john@example.com,Software Engineer,Example Corp,San Francisco,https://linkedin.com/in/johndoe\n" \
        "Jane Smith,jane@testcorp.com,Product Manager,Test Corp,New York,https://linkedin.com/in/janesmith"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'imports people successfully' do
        result = service.perform
        puts "Service result: #{result.success?}"
        puts "Service message: #{result.message}"
        puts "Service error: #{result.error}"
        puts "Service data: #{result.data}"
        puts "Person count: #{Person.count}"

        expect(result.success?).to be true
        expect(result.data[:imported]).to eq(2)
        expect(result.data[:failed]).to eq(0)
      end

      it 'creates audit log entry' do
        expect { service.perform }.to change(ServiceAuditLog, :count).by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.service_name).to eq('person_import')
        expect(audit_log.auditable).to eq(user)
        expect(audit_log.status).to eq('success')
      end

      it 'includes import tag in audit metadata' do
        service.perform

        audit_log = ServiceAuditLog.last
        expect(audit_log.metadata['import_tag']).to be_present
        expect(audit_log.metadata['import_tag']).to eq(service.import_tag)
      end

      it 'maps CSV columns correctly' do
        service.perform

        person = Person.find_by(email: 'john@example.com')
        expect(person.name).to eq('John Doe')
        expect(person.title).to eq('Software Engineer')
        expect(person.company_name).to eq('Example Corp')
        expect(person.location).to eq('San Francisco')
        expect(person.profile_url).to eq('https://linkedin.com/in/johndoe')
      end

      it 'assigns import tag to imported people' do
        service.perform

        person = Person.find_by(email: 'john@example.com')
        expect(person.import_tag).to be_present
        expect(person.import_tag).to start_with('import_')
        expect(person.import_tag).to include(user.email.split('@').first)
      end

      it 'generates unique import tags' do
        expect(service.import_tag).to be_present
        expect(service.import_tag).to match(/\Aimport_\w+_\d{8}_\d{6}\z/)
      end
    end

    context 'with first name and last name columns' do
      let(:csv_content) do
        "First name,Last name,Email,Title\n" \
        "John,Doe,john@example.com,Engineer\n" \
        "Jane,Smith,jane@example.com,Manager"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'builds full name from first and last name' do
        service.perform

        person = Person.find_by(email: 'john@example.com')
        expect(person.name).to eq('John Doe')

        person2 = Person.find_by(email: 'jane@example.com')
        expect(person2.name).to eq('Jane Smith')
      end
    end

    context 'with duplicate emails' do
      let!(:existing_person) { create(:person, email: 'john@example.com', name: 'John Original', title: 'Old Title') }
      let(:csv_content) do
        "Name,Email,Title\n" \
        "John Updated,john@example.com,New Title"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'merges with existing person, imported data overwrites' do
        expect { service.perform }.not_to change(Person, :count)

        result = service.perform
        expect(result.success?).to be true
        expect(result.data[:updated]).to eq(1)
        expect(result.data[:imported]).to eq(0)

        existing_person.reload
        expect(existing_person.name).to eq('John Updated')
        expect(existing_person.title).to eq('New Title')
        expect(existing_person.import_tag).to eq(service.import_tag)
      end
    end

    context 'with duplicate LinkedIn profiles' do
      let!(:existing_person) { create(:person,
        email: 'different@example.com',
        name: 'John Original',
        profile_url: 'https://linkedin.com/in/johndoe',
        title: 'Old Title'
      ) }
      let(:csv_content) do
        "Name,Email,Title,Linkedin\n" \
        "John Updated,john@example.com,New Title,https://linkedin.com/in/johndoe"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'merges with existing person by LinkedIn URL' do
        expect { service.perform }.not_to change(Person, :count)

        result = service.perform
        expect(result.success?).to be true
        expect(result.data[:updated]).to eq(1)

        existing_person.reload
        expect(existing_person.name).to eq('John Updated')
        expect(existing_person.title).to eq('New Title')
        expect(existing_person.email).to eq('john@example.com') # Email gets updated
        expect(existing_person.profile_url).to eq('https://linkedin.com/in/johndoe')
        expect(existing_person.import_tag).to eq(service.import_tag)
      end
    end

    context 'with person having both email and LinkedIn matching different records' do
      let!(:person_by_email) { create(:person,
        email: 'john@example.com',
        name: 'John Email',
        profile_url: 'https://linkedin.com/in/john-email'
      ) }
      let!(:person_by_linkedin) { create(:person,
        email: 'john.linkedin@example.com',
        name: 'John LinkedIn',
        profile_url: 'https://linkedin.com/in/johndoe'
      ) }
      let(:csv_content) do
        "Name,Email,Title,Linkedin\n" \
        "John Merged,john@example.com,New Title,https://linkedin.com/in/johndoe"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'merges with person found by email (email takes precedence)' do
        expect { service.perform }.to change(Person, :count).by(-1) # Two people merge into one

        result = service.perform
        expect(result.success?).to be true
        expect(result.data[:updated]).to eq(1)

        person_by_email.reload
        expect(person_by_email.name).to eq('John Merged')
        expect(person_by_email.title).to eq('New Title')
        expect(person_by_email.profile_url).to eq('https://linkedin.com/in/johndoe') # LinkedIn gets updated

        # The other person should be deleted
        expect { person_by_linkedin.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with partial data that should not overwrite existing data' do
      let!(:existing_person) { create(:person,
        email: 'john@example.com',
        name: 'John Original',
        title: 'Original Title',
        location: 'Original Location'
      ) }
      let(:csv_content) do
        "Name,Email,Title\n" \
        "John Updated,john@example.com,New Title"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'does not overwrite existing data with blank values' do
        service.perform

        existing_person.reload
        expect(existing_person.name).to eq('John Updated')      # Updated from CSV
        expect(existing_person.title).to eq('New Title')       # Updated from CSV
        expect(existing_person.location).to eq('Original Location') # Preserved (not in CSV)
      end
    end

    context 'with invalid email addresses' do
      let(:csv_content) do
        "Name,Email,Title\n" \
        "John Doe,invalid-email,Engineer\n" \
        "Jane Smith,jane@example.com,Manager"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'skips invalid emails and imports valid ones' do
        result = nil
        expect { result = service.perform }.to change(Person, :count).by(1)

        expect(result.success?).to be false # Has failures
        expect(result.data[:imported]).to eq(1)
        expect(result.data[:failed]).to eq(1)

        # Valid person should be imported
        expect(Person.find_by(email: 'jane@example.com')).to be_present
        # Invalid email should not be imported
        expect(Person.find_by(name: 'John Doe')).to be_nil
      end
    end

    context 'with missing email' do
      let(:csv_content) do
        "Name,Email,Title\n" \
        "John Doe,,Engineer"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'fails to import person without email' do
        result = nil
        expect { result = service.perform }.not_to change(Person, :count)

        expect(result.success?).to be false
        expect(result.data[:failed]).to eq(1)
      end
    end

    context 'with email verification status' do
      let(:csv_content) do
        "Name,Email,Email Status,Title\n" \
        "John Doe,john@example.com,valid,Engineer\n" \
        "Jane Smith,jane@example.com,invalid,Manager"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'maps email verification status' do
        service.perform

        john = Person.find_by(email: 'john@example.com')
        expect(john.email_verification_status).to eq('valid')
        expect(john.email_verification_checked_at).to be_present

        jane = Person.find_by(email: 'jane@example.com')
        expect(jane.email_verification_status).to eq('invalid')
      end
    end

    context 'with company matching' do
      let!(:existing_company) { create(:company, company_name: 'Example Corp') }
      let(:csv_content) do
        "Name,Email,Company Name\n" \
        "John Doe,john@example.com,Example Corp"
      end
      let(:csv_file) { create_csv_file(csv_content) }

      it 'associates person with existing company' do
        service.perform

        person = Person.find_by(email: 'john@example.com')
        expect(person.company_id).to eq(existing_company.id)
        expect(person.company_name).to eq('Example Corp')
      end
    end

    context 'when service is disabled' do
      before do
        ServiceConfiguration.find_by(service_name: 'person_import').update!(active: false)
      end

      let(:csv_file) { create_csv_file("Name,Email\nJohn,john@example.com") }

      it 'returns error without processing' do
        expect { service.perform }.not_to change(Person, :count)

        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to include('Service is disabled')
      end
    end

    context 'with no file provided' do
      let(:service) { described_class.new(file: nil, user: user) }

      it 'returns error' do
        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to include('No file provided')
      end
    end

    context 'with invalid file type' do
      let(:txt_file) do
        file = Tempfile.new([ 'test', '.txt' ])
        file.write('not a csv')
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'test.txt',
          type: 'text/plain'
        )
      end

      let(:service) { described_class.new(file: txt_file, user: user) }

      it 'returns error for non-CSV file' do
        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to include('Please upload a CSV file')
      end
    end

    context 'with malformed CSV' do
      let(:csv_file) { create_csv_file("Name,Email\n\"Unclosed quote,john@example.com") }

      it 'handles CSV parsing errors' do
        result = service.perform
        expect(result.success?).to be false
        expect(result.data[:result].csv_errors).not_to be_empty
      end
    end
  end

  private

  def create_csv_file(content, filename: 'test.csv')
    file = Tempfile.new([ 'test', '.csv' ])
    file.write(content)
    file.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: filename,
      type: 'text/csv'
    )
  end
end
