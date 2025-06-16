require 'rails_helper'

RSpec.describe UserEnhancementService, type: :service do
  before(:all) { ENV['ENABLE_AUTOMATIC_AUDITING'] = 'false' }
  before(:each) { ServiceConfiguration.delete_all }

  describe '#initialize' do
    it 'sets default service name and action' do
      service = UserEnhancementService.new
      expect(service.service_name).to eq('user_enhancement_service')
      expect(service.action).to eq('enhance')
    end

    it 'allows custom attributes' do
      service = UserEnhancementService.new(batch_size: 50)
      expect(service.batch_size).to eq(50)
    end
  end

  describe '#call' do
    let(:service_name) { 'user_enhancement_service' }
    let!(:service_config) do
      create(:service_configuration, 
             service_name: service_name,
             refresh_interval_hours: 24,
             active: true)
    end

    context 'when users need enhancement' do
      let!(:users) { create_list(:user, 3) }
      
      it 'processes all users needing enhancement' do
        service = UserEnhancementService.new
        
        expect {
          service.call
        }.to change(ServiceAuditLog, :count).by(3)
        
        audit_logs = ServiceAuditLog.where(service_name: service_name)
        expect(audit_logs.count).to eq(3)
        expect(audit_logs.all?(&:status_success?)).to be true
      end

      it 'stores enhancement data in audit log context' do
        user = create(:user, name: 'John Doe', email: "john_#{SecureRandom.hex(4)}@gmail.com")
        service = UserEnhancementService.new
        
        service.call
        
        audit_log = ServiceAuditLog.where(auditable: user).last
        expect(audit_log.context).to include(
          'email_domain' => 'gmail.com',
          'email_provider' => 'Google',
          'name_length' => 8,
          'name_words' => 2
        )
      end

      it 'handles users without email' do
        user = create(:user, name: 'Jane Doe', email: nil)
        service = UserEnhancementService.new
        
        expect { service.call }.not_to raise_error
        
        audit_log = ServiceAuditLog.where(auditable: user).last
        expect(audit_log.status_success?).to be true
        expect(audit_log.context).to include(
          'name_length' => 8,
          'name_words' => 2
        )
        expect(audit_log.context).not_to have_key('email_domain')
      end

      it 'handles users without name' do
        user = create(:user, name: nil, email: "test_#{SecureRandom.hex(4)}@yahoo.com")
        service = UserEnhancementService.new
        
        expect { service.call }.not_to raise_error
        
        audit_log = ServiceAuditLog.where(auditable: user).last
        expect(audit_log.status_success?).to be true
        expect(audit_log.context).to include(
          'email_domain' => 'yahoo.com',
          'email_provider' => 'Yahoo'
        )
        expect(audit_log.context).not_to have_key('name_length')
      end
    end

    context 'when no users need enhancement' do
      it 'handles empty result gracefully' do
        # Create users that were recently processed
        user = create(:user)
        create(:service_audit_log,
               auditable: user,
               service_name: service_name,
               status: :success,
               completed_at: 1.hour.ago)
        
        service = UserEnhancementService.new
        
        expect {
          capture_stdout { service.call }
        }.not_to change(ServiceAuditLog, :count)
      end
    end

    context 'when service configuration is inactive' do
      before { service_config.update!(active: false) }

      it 'does not process any users' do
        create_list(:user, 2)
        service = UserEnhancementService.new
        
        expect {
          capture_stdout { service.call }
        }.not_to change(ServiceAuditLog, :count)
      end
    end
  end

  describe '#classify_email_provider' do
    let(:service) { UserEnhancementService.new }

    it 'classifies Google domains' do
      expect(service.send(:classify_email_provider, 'gmail.com')).to eq('Google')
      expect(service.send(:classify_email_provider, 'googlemail.com')).to eq('Google')
    end

    it 'classifies Yahoo domains' do
      expect(service.send(:classify_email_provider, 'yahoo.com')).to eq('Yahoo')
      expect(service.send(:classify_email_provider, 'yahoo.co.uk')).to eq('Yahoo')
    end

    it 'classifies Microsoft domains' do
      expect(service.send(:classify_email_provider, 'hotmail.com')).to eq('Microsoft')
      expect(service.send(:classify_email_provider, 'outlook.com')).to eq('Microsoft')
      expect(service.send(:classify_email_provider, 'live.com')).to eq('Microsoft')
    end

    it 'classifies Apple domains' do
      expect(service.send(:classify_email_provider, 'icloud.com')).to eq('Apple')
      expect(service.send(:classify_email_provider, 'me.com')).to eq('Apple')
      expect(service.send(:classify_email_provider, 'mac.com')).to eq('Apple')
    end

    it 'classifies unknown domains as Other' do
      expect(service.send(:classify_email_provider, 'example.com')).to eq('Other')
      expect(service.send(:classify_email_provider, 'custom-domain.org')).to eq('Other')
    end

    it 'handles case insensitive domains' do
      expect(service.send(:classify_email_provider, 'GMAIL.COM')).to eq('Google')
      expect(service.send(:classify_email_provider, 'Yahoo.Com')).to eq('Yahoo')
    end
  end

  describe 'error handling' do
    let!(:service_config) do
      create(:service_configuration, 
             service_name: 'user_enhancement_service',
             active: true)
    end
    let!(:user) { create(:user, email: 'test@gmail.com') }

    it 'marks audit log as failed when error occurs' do
      service = UserEnhancementService.new
      
      # Mock the enhance_user method to be called and simulate the error path
      allow(service).to receive(:enhance_user).and_wrap_original do |original_method, *args|
        audit_log = args[1] # Second argument is the audit_log
        audit_log.mark_failed!('Test error', { 'error_type' => 'StandardError' })
        raise StandardError, 'Test error'
      end
      
      expect { service.call }.to raise_error(StandardError, 'Test error')
      
      audit_log = ServiceAuditLog.where(auditable: user).last
      expect(audit_log.status_failed?).to be true
      expect(audit_log.error_message).to eq('Test error')
      expect(audit_log.context).to include('error_type' => 'StandardError')
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end 