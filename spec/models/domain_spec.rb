require 'rails_helper'

RSpec.describe Domain, type: :model do
  describe 'validations' do
    it 'validates presence of domain' do
      domain = Domain.new(www: true, mx: false)
      expect(domain).not_to be_valid
      expect(domain.errors[:domain]).to include("can't be blank")
    end

    it 'validates uniqueness of domain' do
      create(:domain, domain: 'example.com')
      domain = Domain.new(domain: 'example.com')
      expect(domain).not_to be_valid
      expect(domain.errors[:domain]).to include('has already been taken')
    end
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
    let!(:untested_domain) { create(:domain, dns: nil) }
    let!(:active_domain) { create(:domain, dns: true) }
    let!(:inactive_domain) { create(:domain, dns: false) }
    let!(:www_domain) { create(:domain, www: true) }
    let!(:mx_domain) { create(:domain, mx: true) }

    it 'returns untested domains' do
      expect(Domain.untested).to include(untested_domain)
      expect(Domain.untested).not_to include(active_domain, inactive_domain)
    end

    it 'returns dns_active domains' do
      expect(Domain.dns_active).to include(active_domain)
      expect(Domain.dns_active).not_to include(untested_domain, inactive_domain)
    end

    it 'returns dns_inactive domains' do
      expect(Domain.dns_inactive).to include(inactive_domain)
      expect(Domain.dns_inactive).not_to include(untested_domain, active_domain)
    end

    it 'returns domains with www' do
      expect(Domain.with_www).to include(www_domain)
    end

    it 'returns domains with mx' do
      expect(Domain.with_mx).to include(mx_domain)
    end
  end

  describe '#needs_dns_test?' do
    let!(:config) { create(:service_configuration, service_name: 'domain_dns_testing_v1', refresh_interval_hours: 24) }

    it 'returns true for untested domains' do
      domain = create(:domain, dns: nil)
      expect(domain.needs_dns_test?).to be true
    end

    it 'returns false for recently tested domains' do
      domain = create(:domain, dns: true)
      create(:service_audit_log,
             auditable: domain,
             service_name: 'domain_dns_testing_v1',
             status: :success,
             completed_at: 1.hour.ago)
      
      expect(domain.needs_dns_test?).to be false
    end

    it 'returns true for domains tested long ago' do
      domain = create(:domain, dns: true)
      create(:service_audit_log,
             auditable: domain,
             service_name: 'domain_dns_testing_v1',
             status: :success,
             completed_at: 2.days.ago)
      
      expect(domain.needs_dns_test?).to be true
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

  describe '.needing_service integration' do
    let!(:config) { create(:service_configuration, service_name: 'domain_dns_testing_v1', refresh_interval_hours: 24) }
    let!(:untested_domain) { create(:domain, dns: nil) }
    let!(:recently_tested) { create(:domain, dns: true) }
    let!(:old_tested) { create(:domain, dns: false) }

    before do
      # Recently tested domain
      create(:service_audit_log,
             auditable: recently_tested,
             service_name: 'domain_dns_testing_v1',
             status: :success,
             completed_at: 1.hour.ago)

      # Old tested domain
      create(:service_audit_log,
             auditable: old_tested,
             service_name: 'domain_dns_testing_v1',
             status: :success,
             completed_at: 2.days.ago)
    end

    it 'returns domains that need testing' do
      needing_testing = Domain.needing_service('domain_dns_testing_v1')
      
      expect(needing_testing).to include(untested_domain, old_tested)
      expect(needing_testing).not_to include(recently_tested)
    end
  end
end
