require 'rails_helper'

RSpec.describe ServiceConfiguration, type: :model do
  describe 'validations' do
    subject { build(:service_configuration) }
    
    it { should validate_presence_of(:service_name) }
    it { should validate_uniqueness_of(:service_name) }
    it { should validate_length_of(:service_name).is_at_most(100) }
    it { should validate_numericality_of(:refresh_interval_hours).is_greater_than(0) }
    it { should validate_numericality_of(:batch_size).is_greater_than(0) }
    it { should validate_numericality_of(:retry_attempts).is_greater_than_or_equal_to(0) }
  end

  describe 'default values' do
    let(:config) { ServiceConfiguration.new(service_name: "test_service_#{SecureRandom.hex(8)}") }

    it 'sets default refresh_interval_hours to 720' do
      expect(config.refresh_interval_hours).to eq(720)
    end

    it 'sets default active to true' do
      expect(config.active).to be true
    end

    it 'sets default batch_size to 1000' do
      expect(config.batch_size).to eq(1000)
    end

    it 'sets default retry_attempts to 3' do
      expect(config.retry_attempts).to eq(3)
    end

    it 'sets default depends_on_services to empty array' do
      expect(config.depends_on_services).to eq([])
    end

    it 'sets default settings to empty hash' do
      expect(config.settings).to eq({})
    end
  end

  describe 'scopes' do
    let!(:active_config) { create(:service_configuration, active: true, service_name: "active_config_#{SecureRandom.hex(8)}") }
    let!(:inactive_config) { create(:service_configuration, active: false, service_name: "inactive_config_#{SecureRandom.hex(8)}") }
    let!(:frequent_config) { create(:service_configuration, refresh_interval_hours: 24, service_name: "frequent_config_#{SecureRandom.hex(8)}") }
    let!(:infrequent_config) { create(:service_configuration, refresh_interval_hours: 720, service_name: "infrequent_config_#{SecureRandom.hex(8)}") }

    describe '.active' do
      it 'returns only active configurations' do
        expect(ServiceConfiguration.active).to contain_exactly(active_config, frequent_config, infrequent_config)
      end
    end

    describe '.inactive' do
      it 'returns only inactive configurations' do
        expect(ServiceConfiguration.inactive).to contain_exactly(inactive_config)
      end
    end

    describe '.frequent_refresh' do
      it 'returns configurations with refresh interval less than specified hours' do
        expect(ServiceConfiguration.frequent_refresh(48)).to contain_exactly(frequent_config)
      end
    end
  end

  describe 'instance methods' do
    let(:config) { ServiceConfiguration.new(service_name: "test_service_#{SecureRandom.hex(8)}") }

    describe '#activate!' do
      it 'sets active to true' do
        config.update!(active: false)
        config.activate!
        expect(config.reload).to be_active
      end
    end

    describe '#deactivate!' do
      it 'sets active to false' do
        config.deactivate!
        expect(config.reload).not_to be_active
      end
    end

    describe '#add_dependency' do
      it 'adds service to depends_on_services array' do
        config.add_dependency('user_enhancement_service')
        expect(config.depends_on_services).to include('user_enhancement_service')
      end

      it 'does not add duplicate dependencies' do
        config.add_dependency('user_enhancement_service')
        config.add_dependency('user_enhancement_service')
        expect(config.depends_on_services.count('user_enhancement_service')).to eq(1)
      end
    end

    describe '#remove_dependency' do
      it 'removes service from depends_on_services array' do
        config.update!(depends_on_services: ['user_enhancement_service', 'domain_testing_service'])
        config.remove_dependency('user_enhancement_service')
        expect(config.depends_on_services).not_to include('user_enhancement_service')
        expect(config.depends_on_services).to include('domain_testing_service')
      end
    end

    describe '#update_setting' do
      it 'updates a specific setting' do
        config.update_setting('timeout_seconds', 30)
        expect(config.settings['timeout_seconds']).to eq(30)
      end

      it 'merges with existing settings' do
        config.update!(settings: { 'existing_key' => 'existing_value' })
        config.update_setting('new_key', 'new_value')
        expect(config.settings).to eq({
          'existing_key' => 'existing_value',
          'new_key' => 'new_value'
        })
      end
    end

    describe '#get_setting' do
      it 'returns setting value' do
        config.update!(settings: { 'timeout_seconds' => 30 })
        expect(config.get_setting('timeout_seconds')).to eq(30)
      end

      it 'returns default value when setting does not exist' do
        expect(config.get_setting('nonexistent_key', 'default')).to eq('default')
      end
    end

    describe '#needs_refresh?' do
      let(:last_run_time) { 25.hours.ago }

      it 'returns true when last run is older than refresh interval' do
        config.update!(refresh_interval_hours: 24)
        expect(config.needs_refresh?(last_run_time)).to be true
      end

      it 'returns false when last run is within refresh interval' do
        config.update!(refresh_interval_hours: 48)
        expect(config.needs_refresh?(last_run_time)).to be false
      end

      it 'returns true when last_run_time is nil' do
        expect(config.needs_refresh?(nil)).to be true
      end
    end

    describe '#dependencies_met?' do
      let!(:dep1_config) { create(:service_configuration, service_name: "dependency_1_service_#{SecureRandom.hex(8)}") }
      let!(:dep2_config) { create(:service_configuration, service_name: "dependency_2_service_#{SecureRandom.hex(8)}") }

      before do
        config.update!(depends_on_services: ['dependency_1_service', 'dependency_2_service'])
      end

      it 'returns true when all dependencies are active' do
        expect(config.dependencies_met?).to be true
      end

      it 'returns false when any dependency is inactive' do
        dep1_config.update!(active: false)
        expect(config.dependencies_met?).to be false
      end

      it 'returns true when no dependencies are specified' do
        config.update!(depends_on_services: [])
        expect(config.dependencies_met?).to be true
      end
    end
  end

  describe 'class methods' do
    describe '.for_service' do
      let!(:config) { create(:service_configuration, service_name: "test_service_#{SecureRandom.hex(8)}") }

      it 'finds configuration by service name' do
        expect(ServiceConfiguration.for_service('test_service')).to eq(config)
      end

      it 'returns nil for non-existent service' do
        expect(ServiceConfiguration.for_service('nonexistent_service')).to be_nil
      end
    end

    describe '.create_default' do
      it 'creates configuration with default values' do
        config = ServiceConfiguration.create_default('new_service')
        expect(config.service_name).to eq('new_service')
        expect(config.active).to be true
        expect(config.refresh_interval_hours).to eq(720)
        expect(config.batch_size).to eq(1000)
        expect(config.retry_attempts).to eq(3)
      end

      it 'allows overriding default values' do
        config = ServiceConfiguration.create_default('new_service', batch_size: 500, active: false)
        expect(config.batch_size).to eq(500)
        expect(config.active).to be false
      end
    end

    describe '.bulk_update_settings' do
      let!(:config1) { create(:service_configuration, service_name: "service_1_#{SecureRandom.hex(8)}") }
      let!(:config2) { create(:service_configuration, service_name: "service_2_#{SecureRandom.hex(8)}") }

      it 'updates settings for multiple services' do
        ServiceConfiguration.bulk_update_settings(
          'service_1' => { 'timeout' => 30 },
          'service_2' => { 'retries' => 5 }
        )

        expect(config1.reload.settings['timeout']).to eq(30)
        expect(config2.reload.settings['retries']).to eq(5)
      end
    end
  end

  describe 'callbacks' do
    describe 'after_create' do
      it 'logs configuration creation' do
        expect(Rails.logger).to receive(:info).with(/Service configuration created for/)
        create(:service_configuration, service_name: 'test_service')
      end
    end

    describe 'after_update' do
      let(:config) { create(:service_configuration) }

      it 'logs configuration updates' do
        # Clear the creation log expectation first
        allow(Rails.logger).to receive(:info)
        
        expect(Rails.logger).to receive(:info).with(/Service configuration updated for/)
        config.update!(batch_size: 2000)
      end
    end
  end
end 