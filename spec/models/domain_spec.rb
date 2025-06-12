require 'rails_helper'

RSpec.describe Domain, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:domain) }
    it { should validate_uniqueness_of(:domain) }
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
    let!(:active_dns) { create(:domain, dns: true) }
    let!(:inactive_dns) { create(:domain, dns: false) }
    let!(:untested_dns) { create(:domain, dns: nil) }
    let!(:active_www) { create(:domain, www: true) }
    let!(:inactive_www) { create(:domain, www: false) }
    let!(:untested_www) { create(:domain, www: nil) }

    describe '.dns_active' do
      it 'returns domains with active DNS' do
        expect(Domain.dns_active).to include(active_dns)
        expect(Domain.dns_active).not_to include(inactive_dns, untested_dns)
      end
    end

    describe '.dns_inactive' do
      it 'returns domains with inactive DNS' do
        expect(Domain.dns_inactive).to include(inactive_dns)
        expect(Domain.dns_inactive).not_to include(active_dns, untested_dns)
      end
    end

    describe '.untested' do
      it 'returns domains with untested DNS' do
        expect(Domain.untested).to include(untested_dns)
        expect(Domain.untested).not_to include(active_dns, inactive_dns)
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
    let!(:config) { create(:service_configuration, service_name: 'domain_testing_service', refresh_interval_hours: 24) }
    let(:domain) { create(:domain) }

    context 'when DNS has never been tested' do
      it 'returns true' do
        expect(domain.needs_testing?).to be true
      end
    end

    context 'when DNS was tested recently' do
      before do
        create(:service_audit_log,
          auditable: domain,
          service_name: 'domain_testing_service',
          created_at: 1.hour.ago,
          status: :success
        )
      end

      it 'returns false' do
        expect(domain.needs_testing?).to be false
      end
    end

    context 'when DNS was tested long ago' do
      before do
        create(:service_audit_log,
          auditable: domain,
          service_name: 'domain_testing_service',
          created_at: 48.hours.ago,
          status: :success
        )
      end

      it 'returns true' do
        expect(domain.needs_testing?).to be true
      end
    end
  end

  describe '#needs_www_testing?' do
    let!(:config) { create(:service_configuration, service_name: 'domain_testing_service', refresh_interval_hours: 24) }
    let(:domain) { create(:domain, dns: true) }

    context 'when WWW has never been tested' do
      it 'returns true' do
        expect(domain.needs_www_testing?).to be true
      end
    end

    context 'when WWW was tested recently' do
      before do
        create(:service_audit_log,
          auditable: domain,
          service_name: 'domain_a_record_testing_v1',
          created_at: 1.hour.ago,
          status: :success
        )
      end

      it 'returns false' do
        expect(domain.needs_www_testing?).to be false
      end
    end

    context 'when WWW was tested long ago' do
      before do
        create(:service_audit_log,
          auditable: domain,
          service_name: 'domain_a_record_testing_v1',
          created_at: 48.hours.ago,
          status: :success
        )
      end

      it 'returns true' do
        expect(domain.needs_www_testing?).to be true
      end
    end

    context 'when DNS is inactive' do
      let(:domain) { create(:domain, dns: false) }

      it 'returns false' do
        expect(domain.needs_www_testing?).to be false
      end
    end
  end

  describe '.needing_service' do
    let!(:config) { create(:service_configuration, service_name: 'domain_testing_service', refresh_interval_hours: 24) }
    let!(:never_tested) { create(:domain) }
    let!(:tested_recently) { create(:domain) }
    let!(:tested_long_ago) { create(:domain) }

    before do
      create(:service_audit_log,
        auditable: tested_recently,
        service_name: 'domain_testing_service',
        created_at: 1.hour.ago,
        status: :success
      )

      create(:service_audit_log,
        auditable: tested_long_ago,
        service_name: 'domain_testing_service',
        created_at: 48.hours.ago,
        status: :success
      )
    end

    it 'returns domains needing testing' do
      needing_testing = Domain.needing_service('domain_testing_service')
      expect(needing_testing).to include(never_tested, tested_long_ago)
      expect(needing_testing).not_to include(tested_recently)
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
