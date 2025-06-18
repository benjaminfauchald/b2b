require 'rails_helper'

RSpec.describe ServiceConfiguration, type: :model do
  let(:service_name) { 'test_service' }
  let(:refresh_interval) { 24 }
  let(:depends_on) { [ 'other_service' ] }

  before(:each) do
    ServiceConfiguration.delete_all
  end

  describe 'validations' do
    it 'requires a service name' do
      config = build(:service_configuration, service_name: nil)
      expect(config).not_to be_valid
      expect(config.errors[:service_name]).to include("can't be blank")
    end

    it 'requires a unique service name' do
      create(:service_configuration, service_name: service_name)
      config = build(:service_configuration, service_name: service_name)
      expect(config).not_to be_valid
      expect(config.errors[:service_name]).to include('has already been taken')
    end

    it 'requires a positive refresh interval' do
      config = build(:service_configuration, refresh_interval_hours: -1)
      expect(config).not_to be_valid
      expect(config.errors[:refresh_interval_hours]).to include('must be greater than 0')
    end
  end

  describe 'active scope' do
    before do
      create(:service_configuration, service_name: 'active_service', active: true)
      create(:service_configuration, service_name: 'inactive_service', active: false)
    end

    it 'finds only active services' do
      expect(ServiceConfiguration.active.count).to eq(1)
      expect(ServiceConfiguration.active.first.service_name).to eq('active_service')
    end
  end

  describe '.active?' do
    before do
      create(:service_configuration, service_name: service_name, active: true)
    end

    it 'returns true for active services' do
      expect(ServiceConfiguration.active?(service_name)).to be true
    end

    it 'returns false for inactive services' do
      create(:service_configuration, service_name: 'inactive_service', active: false)
      expect(ServiceConfiguration.active?('inactive_service')).to be false
    end

    it 'returns false for non-existent services' do
      expect(ServiceConfiguration.active?('non_existent')).to be false
    end
  end

  describe 'dependencies' do
    it 'stores and retrieves dependencies' do
      config = create(:service_configuration,
        service_name: service_name,
        depends_on_services: depends_on
      )

      expect(config.depends_on_services).to eq(depends_on)
    end

    it 'handles empty dependencies' do
      config = create(:service_configuration,
        service_name: service_name,
        depends_on_services: []
      )

      expect(config.depends_on_services).to eq([])
    end
  end
end
