# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhantomBusterImportJob, type: :job do
  include ActiveJob::TestHelper
  
  let(:valid_csv_path) { Rails.root.join('tmp', 'test_phantom_buster.csv') }
  let(:valid_csv_content) do
    <<~CSV
      profileUrl,fullName,firstName,lastName,companyName,title,companyId,companyUrl,regularCompanyUrl,summary,titleDescription,industry,companyLocation,location,durationInRole,durationInCompany,pastExperienceCompanyName,pastExperienceCompanyUrl,pastExperienceCompanyTitle,pastExperienceDate,pastExperienceDuration,connectionDegree,profileImageUrl,sharedConnectionsCount,name,vmid,linkedInProfileUrl,isPremium,isOpenLink,query,timestamp,defaultProfileUrl
      "https://www.linkedin.com/in/test-job-user",Test Job User,Test,Job User,Test Corp,Engineer,12345,https://linkedin.com/company/test,https://test.com,Bio,,Tech,"Oslo, Norway","Oslo, Norway",1 year,2 years,,,,,,2nd,https://example.com/photo.jpg,10,Test Job User,JOB123,https://www.linkedin.com/in/test-job-user,false,true,test,2025-07-10T10:00:00Z,https://linkedin.com/in/test-job-user
    CSV
  end
  
  before do
    File.write(valid_csv_path, valid_csv_content)
  end
  
  after do
    File.delete(valid_csv_path) if File.exist?(valid_csv_path)
  end
  
  describe '#perform' do
    it 'enqueues the job' do
      ActiveJob::Base.queue_adapter = :test
      
      expect {
        described_class.perform_later(valid_csv_path.to_s)
      }.to have_enqueued_job(described_class)
        .with(valid_csv_path.to_s)
        .on_queue('imports')
    end
    
    context 'with valid CSV' do
      it 'imports records successfully' do
        expect {
          described_class.perform_now(valid_csv_path)
        }.to change(Person, :count).by(1)
        
        person = Person.last
        expect(person.name).to eq('Test Job User')
        expect(person.company_name).to eq('Test Corp')
      end
      
      it 'passes options to import service' do
        service_double = instance_double(PhantomBusterImportService)
        allow(PhantomBusterImportService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:detect_format).and_return(true)
        allow(service_double).to receive(:import).with(hash_including(import_tag: 'test_tag')).and_return(true)
        allow(service_double).to receive(:import_results).and_return({
          total: 1, successful: 1, failed: 0, duplicates: 0
        })
        
        described_class.perform_now(valid_csv_path, import_tag: 'test_tag')
        
        expect(service_double).to have_received(:import).with(import_tag: 'test_tag')
      end
      
      it 'deletes file after import when requested' do
        described_class.perform_now(valid_csv_path, delete_after_import: true)
        
        expect(File.exist?(valid_csv_path)).to be false
      end
      
      it 'keeps file when delete not requested' do
        described_class.perform_now(valid_csv_path, delete_after_import: false)
        
        expect(File.exist?(valid_csv_path)).to be true
      end
    end
    
    context 'with invalid CSV' do
      let(:invalid_csv_path) { Rails.root.join('tmp', 'invalid_job.csv') }
      
      before do
        File.write(invalid_csv_path, "name,email\nJohn,john@example.com")
      end
      
      after do
        File.delete(invalid_csv_path) if File.exist?(invalid_csv_path)
      end
      
      it 'logs error and does not raise' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        
        expect {
          described_class.perform_now(invalid_csv_path)
        }.not_to raise_error
      end
      
      it 'does not import any records' do
        expect {
          described_class.perform_now(invalid_csv_path)
        }.not_to change(Person, :count)
      end
    end
    
    context 'with import errors' do
      it 'handles and logs partial failures' do
        service_double = instance_double(PhantomBusterImportService)
        allow(PhantomBusterImportService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:detect_format).and_return(true)
        allow(service_double).to receive(:import).and_return(true)
        allow(service_double).to receive(:import_results).and_return({
          total: 10, successful: 8, failed: 2, duplicates: 0,
          errors: [
            { row: 3, error: 'Invalid data' },
            { row: 7, error: 'Duplicate record' }
          ]
        })
        
        expect(Rails.logger).to receive(:info).at_least(:once)
        
        described_class.perform_now(valid_csv_path)
      end
    end
    
    context 'with unexpected errors' do
      it 're-raises error for Sidekiq retry' do
        allow(PhantomBusterImportService).to receive(:new).and_raise(StandardError, 'Unexpected error')
        
        expect {
          described_class.perform_now(valid_csv_path)
        }.to raise_error(StandardError, 'Unexpected error')
      end
    end
  end
end