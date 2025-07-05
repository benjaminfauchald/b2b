require 'rails_helper'
require 'tempfile'

RSpec.describe PersonImportService, type: :service do
  let(:user) { create(:user) }
  let(:service_config) { create(:service_configuration, service_name: 'person_import', active: true) }

  before do
    service_config
  end

  describe 'ZeroBounce field import functionality' do
    context 'with ZeroBounce CSV data' do
      let(:csv_content) do
        <<~CSV
          Email,Name,ZB Status,ZB Sub Status,ZB Account,ZB Domain,ZB First Name,ZB Last Name,ZB Gender,ZB Free Email,ZB MX Found,ZB MX Record,ZB SMTP Provider,ZB Did You Mean,ZB Last Known Activity,ZB Activity Data Count,ZB Activity Data Types,ZB Activity Data Channels,ZeroBounceQualityScore
          john@example.com,John Doe,valid,mailbox_verified,john,example.com,John,Doe,male,false,true,mx1.example.com,Gmail,"","",10,email_sent,email,8.5
          jane@invalid.com,Jane Smith,invalid,mailbox_not_found,jane,invalid.com,Jane,Smith,female,false,false,"","",jane@invalid.co,"",5,email_bounce,email,2.1
          test@freemail.com,Test User,valid,mailbox_verified,test,freemail.com,Test,User,"",true,true,mx.freemail.com,Yahoo,"","",0,"",email,7.8
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ 'zerobounce_test', '.csv' ])
        file.write(csv_content)
        file.rewind

        # Create mock object with ActionDispatch::Http::UploadedFile interface
        uploaded_file = double('uploaded_file')
        allow(uploaded_file).to receive(:path).and_return(file.path)
        allow(uploaded_file).to receive(:original_filename).and_return('zerobounce_test.csv')
        allow(uploaded_file).to receive(:content_type).and_return('text/csv')
        allow(uploaded_file).to receive(:size).and_return(csv_content.bytesize)

        uploaded_file
      end

      after do
        # Clean up the temporary file
        File.unlink(csv_file.path) if File.exist?(csv_file.path)
      end

      it 'imports ZeroBounce fields correctly' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        expect(result.success?).to be true
        expect(result.data[:imported]).to eq(3)

        # Check first person with complete ZeroBounce data
        john = Person.find_by(email: 'john@example.com')
        expect(john).to be_present
        expect(john.zerobounce_status).to eq('valid')
        expect(john.zerobounce_sub_status).to eq('mailbox_verified')
        expect(john.zerobounce_account).to eq('john')
        expect(john.zerobounce_domain).to eq('example.com')
        expect(john.zerobounce_first_name).to eq('John')
        expect(john.zerobounce_last_name).to eq('Doe')
        expect(john.zerobounce_gender).to eq('male')
        expect(john.zerobounce_free_email).to be false
        expect(john.zerobounce_mx_found).to be true
        expect(john.zerobounce_mx_record).to eq('mx1.example.com')
        expect(john.zerobounce_smtp_provider).to eq('Gmail')
        expect(john.zerobounce_did_you_mean).to be_nil
        expect(john.zerobounce_activity_data_count).to eq(10)
        expect(john.zerobounce_activity_data_types).to eq('email_sent')
        expect(john.zerobounce_activity_data_channels).to eq('email')
        expect(john.zerobounce_quality_score).to eq(8.5)
        expect(john.zerobounce_imported_at).to be_within(1.minute).of(Time.current)
      end

      it 'handles invalid ZeroBounce data correctly' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        # Check second person with invalid status and typo suggestion
        jane = Person.find_by(email: 'jane@invalid.com')
        expect(jane).to be_present
        expect(jane.zerobounce_status).to eq('invalid')
        expect(jane.zerobounce_sub_status).to eq('mailbox_not_found')
        expect(jane.zerobounce_mx_found).to be false
        expect(jane.zerobounce_did_you_mean).to eq('jane@invalid.co')
        expect(jane.zerobounce_quality_score).to eq(2.1)
        expect(jane.zerobounce_activity_data_count).to eq(5)
      end

      it 'handles free email detection' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        # Check third person with free email
        test_user = Person.find_by(email: 'test@freemail.com')
        expect(test_user).to be_present
        expect(test_user.zerobounce_free_email).to be true
        expect(test_user.zerobounce_smtp_provider).to eq('Yahoo')
        expect(test_user.zerobounce_quality_score).to eq(7.8)
        expect(test_user.zerobounce_activity_data_count).to eq(0)
        expect(test_user.zerobounce_activity_data_types).to be_blank
      end

      it 'sets zerobounce_imported_at timestamp' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        Person.all.each do |person|
          expect(person.zerobounce_imported_at).to be_within(1.minute).of(Time.current)
        end
      end
    end

    context 'with partial ZeroBounce data' do
      let(:csv_content) do
        <<~CSV
          Email,Name,ZB Status,ZeroBounceQualityScore
          partial@example.com,Partial User,valid,9.2
          minimal@example.com,Minimal User,,
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ 'partial_zb_test', '.csv' ])
        file.write(csv_content)
        file.rewind

        uploaded_file = double('uploaded_file')
        allow(uploaded_file).to receive(:path).and_return(file.path)
        allow(uploaded_file).to receive(:original_filename).and_return('partial_zb_test.csv')
        allow(uploaded_file).to receive(:content_type).and_return('text/csv')
        allow(uploaded_file).to receive(:size).and_return(csv_content.bytesize)

        uploaded_file
      end

      after do
        # Clean up the temporary file
        File.unlink(csv_file.path) if File.exist?(csv_file.path)
      end

      it 'imports partial ZeroBounce data correctly' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        expect(result.success?).to be true

        # Person with partial data
        partial = Person.find_by(email: 'partial@example.com')
        expect(partial.zerobounce_status).to eq('valid')
        expect(partial.zerobounce_quality_score).to eq(9.2)
        expect(partial.zerobounce_sub_status).to be_nil
        expect(partial.zerobounce_imported_at).to be_present

        # Person with no ZeroBounce data
        minimal = Person.find_by(email: 'minimal@example.com')
        expect(minimal.zerobounce_status).to be_nil
        expect(minimal.zerobounce_quality_score).to be_nil
        expect(minimal.zerobounce_imported_at).to be_nil
      end
    end

    context 'with invalid boolean values' do
      let(:csv_content) do
        <<~CSV
          Email,Name,ZB Free Email,ZB MX Found
          bool1@example.com,Bool Test 1,true,yes
          bool2@example.com,Bool Test 2,false,no
          bool3@example.com,Bool Test 3,1,0
          bool4@example.com,Bool Test 4,invalid,invalid
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ 'bool_test', '.csv' ])
        file.write(csv_content)
        file.rewind

        uploaded_file = double('uploaded_file')
        allow(uploaded_file).to receive(:path).and_return(file.path)
        allow(uploaded_file).to receive(:original_filename).and_return('bool_test.csv')
        allow(uploaded_file).to receive(:content_type).and_return('text/csv')
        allow(uploaded_file).to receive(:size).and_return(csv_content.bytesize)

        uploaded_file
      end

      after do
        # Clean up the temporary file
        File.unlink(csv_file.path) if File.exist?(csv_file.path)
      end

      it 'converts boolean values correctly' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        expect(result.success?).to be true

        # Test true values
        bool1 = Person.find_by(email: 'bool1@example.com')
        expect(bool1.zerobounce_free_email).to be true
        expect(bool1.zerobounce_mx_found).to be true

        # Test false values
        bool2 = Person.find_by(email: 'bool2@example.com')
        expect(bool2.zerobounce_free_email).to be false
        expect(bool2.zerobounce_mx_found).to be false

        # Test numeric values
        bool3 = Person.find_by(email: 'bool3@example.com')
        expect(bool3.zerobounce_free_email).to be true
        expect(bool3.zerobounce_mx_found).to be false

        # Test invalid values
        bool4 = Person.find_by(email: 'bool4@example.com')
        expect(bool4.zerobounce_free_email).to be false
        expect(bool4.zerobounce_mx_found).to be false
      end
    end

    context 'with date/time values' do
      let(:csv_content) do
        <<~CSV
          Email,Name,ZB Last Known Activity
          date1@example.com,Date Test 1,2024-12-01T10:30:00Z
          date2@example.com,Date Test 2,2024-12-01 10:30:00
          date3@example.com,Date Test 3,invalid-date
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ 'date_test', '.csv' ])
        file.write(csv_content)
        file.rewind

        uploaded_file = double('uploaded_file')
        allow(uploaded_file).to receive(:path).and_return(file.path)
        allow(uploaded_file).to receive(:original_filename).and_return('date_test.csv')
        allow(uploaded_file).to receive(:content_type).and_return('text/csv')
        allow(uploaded_file).to receive(:size).and_return(csv_content.bytesize)

        uploaded_file
      end

      after do
        # Clean up the temporary file
        File.unlink(csv_file.path) if File.exist?(csv_file.path)
      end

      it 'parses valid dates and skips invalid ones' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        expect(result.success?).to be true

        # Valid ISO date
        date1 = Person.find_by(email: 'date1@example.com')
        expect(date1.zerobounce_last_known_activity).to be_present
        expect(date1.zerobounce_last_known_activity).to be_a(Time)

        # Valid standard date
        date2 = Person.find_by(email: 'date2@example.com')
        expect(date2.zerobounce_last_known_activity).to be_present
        expect(date2.zerobounce_last_known_activity).to be_a(Time)

        # Invalid date should be nil
        date3 = Person.find_by(email: 'date3@example.com')
        expect(date3.zerobounce_last_known_activity).to be_nil
      end
    end

    context 'without ZeroBounce data' do
      let(:csv_content) do
        <<~CSV
          Email,Name,Title
          regular@example.com,Regular User,Developer
        CSV
      end

      let(:csv_file) do
        file = Tempfile.new([ 'regular_test', '.csv' ])
        file.write(csv_content)
        file.rewind

        uploaded_file = double('uploaded_file')
        allow(uploaded_file).to receive(:path).and_return(file.path)
        allow(uploaded_file).to receive(:original_filename).and_return('regular_test.csv')
        allow(uploaded_file).to receive(:content_type).and_return('text/csv')
        allow(uploaded_file).to receive(:size).and_return(csv_content.bytesize)

        uploaded_file
      end

      after do
        # Clean up the temporary file
        File.unlink(csv_file.path) if File.exist?(csv_file.path)
      end

      it 'imports normally without ZeroBounce fields' do
        service = PersonImportService.new(file: csv_file, user: user)
        result = service.perform

        expect(result.success?).to be true
        expect(result.data[:imported]).to eq(1)

        person = Person.find_by(email: 'regular@example.com')
        expect(person).to be_present
        expect(person.name).to eq('Regular User')
        expect(person.title).to eq('Developer')
        expect(person.zerobounce_status).to be_nil
        expect(person.zerobounce_imported_at).to be_nil
      end
    end
  end

  describe '#map_zerobounce_fields' do
    let(:service) { PersonImportService.new(file: nil, user: user) }

    it 'maps all ZeroBounce fields correctly' do
      row_data = {
        zb_status: 'valid',
        zb_sub_status: 'mailbox_verified',
        zb_account: 'test',
        zb_domain: 'example.com',
        zb_first_name: 'Test',
        zb_last_name: 'User',
        zb_gender: 'male',
        zb_free_email: 'true',
        zb_mx_found: 'yes',
        zb_mx_record: 'mx.example.com',
        zb_smtp_provider: 'Gmail',
        zb_did_you_mean: 'test@example.co',
        zb_last_known_activity: '2024-12-01T10:30:00Z',
        zb_activity_data_count: '5',
        zb_activity_data_types: 'email_sent,email_open',
        zb_activity_data_channels: 'email,web',
        zerobouncequalityscore: '8.5'
      }

      person_attributes = {}
      result = service.send(:map_zerobounce_fields, row_data, person_attributes)

      expect(result[:zerobounce_status]).to eq('valid')
      expect(result[:zerobounce_sub_status]).to eq('mailbox_verified')
      expect(result[:zerobounce_account]).to eq('test')
      expect(result[:zerobounce_domain]).to eq('example.com')
      expect(result[:zerobounce_first_name]).to eq('Test')
      expect(result[:zerobounce_last_name]).to eq('User')
      expect(result[:zerobounce_gender]).to eq('male')
      expect(result[:zerobounce_free_email]).to be true
      expect(result[:zerobounce_mx_found]).to be true
      expect(result[:zerobounce_mx_record]).to eq('mx.example.com')
      expect(result[:zerobounce_smtp_provider]).to eq('Gmail')
      expect(result[:zerobounce_did_you_mean]).to eq('test@example.co')
      expect(result[:zerobounce_last_known_activity]).to be_a(Time)
      expect(result[:zerobounce_activity_data_count]).to eq(5)
      expect(result[:zerobounce_activity_data_types]).to eq('email_sent,email_open')
      expect(result[:zerobounce_activity_data_channels]).to eq('email,web')
      expect(result[:zerobounce_quality_score]).to eq(8.5)
      expect(result[:zerobounce_imported_at]).to be_within(1.second).of(Time.current)
    end

    it 'handles empty row data gracefully' do
      row_data = {}
      person_attributes = {}
      result = service.send(:map_zerobounce_fields, row_data, person_attributes)

      expect(result).to eq(person_attributes)
      expect(result[:zerobounce_imported_at]).to be_nil
    end
  end
end
