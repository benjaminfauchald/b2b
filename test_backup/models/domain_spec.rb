require 'rails_helper'
require 'securerandom'

RSpec.describe Domain, type: :model do
  let(:service_name) { "domain_testing_#{SecureRandom.hex(4)}" }

  describe 'validations' do
    it { should validate_presence_of(:domain) }
    it { should validate_uniqueness_of(:domain) }
  end

  describe 'associations' do
    it { should have_many(:service_audit_logs) }
  end

  describe 'ServiceAuditable concern' do
    it 'includes ServiceAuditable module' do
      expect(Domain.included_modules).to include(ServiceAuditable)
    end

    it 'has many service_audit_logs' do
      association = Domain.reflect_on_association(:service_audit_logs)
      expect(association.macro).to eq :has_many
      expect(association.options[:as]).to eq :auditable
      expect(association.options[:dependent]).to eq :destroy
    end
  end

  describe 'scopes' do
    describe '.dns_active' do
      let!(:active_domain) { create(:domain, dns: true) }
      let!(:inactive_domain) { create(:domain, dns: false) }
      let!(:untested_domain) { create(:domain, dns: nil) }

      it 'returns only domains with dns=true' do
        expect(Domain.dns_active).to include(active_domain)
        expect(Domain.dns_active).not_to include(inactive_domain, untested_domain)
      end
    end

    let!(:active_www) { create(:domain, www: true) }
    let!(:inactive_www) { create(:domain, www: false) }
    let!(:untested_www) { create(:domain, www: nil) }

    describe '.dns_inactive' do
      it 'returns domains with inactive DNS' do
        expect(Domain.dns_inactive).to include(inactive_domain)
        expect(Domain.dns_inactive).not_to include(active_domain, untested_domain)
      end
    end

    describe '.untested' do
      it 'returns domains with untested DNS' do
        expect(Domain.untested).to include(untested_domain)
        expect(Domain.untested).not_to include(active_domain, inactive_domain)
      end
    end

    describe '.www_active' do
      it 'returns domains with active WWW' do
        expect(Domain.www_active).to include(active_www)
        expect(Domain.www_active).not_to include(inactive_www, untested_www)
      end
    end

    describe '.www_inactive' do
      it 'returns domains with inactive WWW' do
        expect(Domain.www_inactive).to include(inactive_www)
        expect(Domain.www_inactive).not_to include(active_www, untested_www)
      end
    end

    describe '.www_untested' do
      it 'returns domains with untested WWW' do
        expect(Domain.www_untested).to include(untested_www)
        expect(Domain.www_untested).not_to include(active_www, inactive_www)
      end
    end
  end

  describe '#needs_testing?' do
    let(:service_name) { "domain_testing_service_#{SecureRandom.hex(8)}" }
    let!(:config) { create(:service_configuration, service_name: service_name, refresh_interval_hours: 24) }
    let(:domain) { create(:domain) }

    context 'when DNS has never been tested' do
      it 'returns true' do
        expect(domain.needs_testing?(service_name)).to be true
      end
    end

    context 'when DNS was tested recently' do
      before do
        create(:service_audit_log, :success, 
               auditable: domain, 
               service_name: service_name, 
               completed_at: 1.hour.ago)
      end

      it 'returns false' do
        expect(domain.needs_testing?(service_name)).to be false
      end
    end

    context 'when DNS was tested long ago' do
      before do
        create(:service_audit_log, :success, 
               auditable: domain, 
               service_name: service_name, 
               completed_at: 25.hours.ago)
      end

      it 'returns true' do
        expect(domain.needs_testing?(service_name)).to be true
      end
    end
  end

  describe '#needs_www_testing?' do
    let(:service_name) { 'domain_a_record_testing' }
    let!(:config) { create(:service_configuration, service_name: service_name, refresh_interval_hours: 24) }
    let(:domain) { create(:domain, dns: true, www: nil) }

    context 'when www is nil' do
      it 'returns true' do
        expect(domain.needs_www_testing?(service_name)).to be true
      end
    end

    context 'when www is not nil' do
      before do
        domain.update!(www: true)
      end

      it 'returns false' do
        expect(domain.needs_www_testing?(service_name)).to be false
      end
    end

    context 'when dns is false' do
      before do
        domain.update!(dns: false)
      end

      it 'returns false' do
        expect(domain.needs_www_testing?(service_name)).to be false
      end
    end

    context 'when dns is nil' do
      before do
        domain.update!(dns: nil)
      end

      it 'returns false' do
        expect(domain.needs_www_testing?(service_name)).to be false
      end
    end
  end

  describe '#needs_mx_testing?' do
    let(:service_name) { 'domain_mx_testing' }
    let!(:config) { create(:service_configuration, service_name: service_name, refresh_interval_hours: 24) }
    let(:domain) { create(:domain, dns: true, www: true, mx: nil) }

    context 'when mx is nil' do
      it 'returns true' do
        expect(domain.needs_mx_testing?(service_name)).to be true
      end
    end

    context 'when mx is not nil' do
      before do
        domain.update!(mx: true)
      end

      it 'returns false' do
        expect(domain.needs_mx_testing?(service_name)).to be false
      end
    end

    context 'when dns is false' do
      before do
        domain.update!(dns: false)
      end

      it 'returns false' do
        expect(domain.needs_mx_testing?(service_name)).to be false
      end
    end

    context 'when dns is nil' do
      before do
        domain.update!(dns: nil)
      end

      it 'returns false' do
        expect(domain.needs_mx_testing?(service_name)).to be false
      end
    end

    context 'when www is false' do
      before do
        domain.update!(www: false)
      end

      it 'returns false' do
        expect(domain.needs_mx_testing?(service_name)).to be false
      end
    end

    context 'when www is nil' do
      before do
        domain.update!(www: nil)
      end

      it 'returns false' do
        expect(domain.needs_mx_testing?(service_name)).to be false
      end
    end
  end

  describe '.needing_service' do
    let(:service_name) { 'domain_testing' }
    let!(:config) { create(:service_configuration, service_name: service_name, refresh_interval_hours: 24) }
    let!(:domain1) { create(:domain) }
    let!(:domain2) { create(:domain) }
    let!(:domain3) { create(:domain) }

    before do
      create(:service_audit_log, :success, 
             auditable: domain2, 
             service_name: service_name, 
             completed_at: 1.hour.ago)
      create(:service_audit_log, :success, 
             auditable: domain3, 
             service_name: service_name, 
             completed_at: 25.hours.ago)
    end

    it 'returns domains needing testing' do
      needing_domains = Domain.needing_service(service_name)
      expect(needing_domains).to include(domain1, domain3)
      expect(needing_domains).not_to include(domain2)
    end
  end

  describe '#test_status' do
    it 'returns "active" for domains with dns: true' do
      domain = create(:domain, dns: true)
      expect(domain.test_status).to eq('active')
    end

    it 'returns "inactive" for domains with dns: false' do
      domain = create(:domain, dns: false)
      expect(domain.test_status).to eq('inactive')
    end

    it 'returns "untested" for domains with dns: nil' do
      domain = create(:domain, dns: nil)
      expect(domain.test_status).to eq('untested')
    end
  end
end
