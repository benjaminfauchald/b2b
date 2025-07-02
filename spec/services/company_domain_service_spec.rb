require 'rails_helper'

RSpec.describe CompanyDomainService do
  let(:company) { create(:company) }
  let(:service) { described_class.new(company, website_url) }

  describe '#execute' do
    context 'with nil website URL' do
      let(:website_url) { nil }

      it 'returns success with nil domain' do
        result = service.execute
        expect(result).to be_success
        expect(result.data[:domain]).to be_nil
      end
    end

    context 'with blank website URL' do
      let(:website_url) { '' }

      it 'returns error' do
        result = service.execute
        expect(result).to be_error
        expect(result.error_message).to include('Invalid domain format')
      end
    end

    context 'with invalid domain format' do
      let(:website_url) { 'not a domain' }

      it 'returns error' do
        result = service.execute
        expect(result).to be_error
        expect(result.error_message).to include('Invalid domain format')
      end
    end

    context 'with valid domain' do
      let(:website_url) { 'example.com' }

      context 'when domain does not exist' do
        it 'creates a new domain' do
          expect { service.execute }.to change(Domain, :count).by(1)
        end

        it 'associates domain with company' do
          result = service.execute
          expect(result).to be_success
          domain = result.data[:domain]
          expect(domain.company).to eq(company)
          expect(domain.domain).to eq('example.com')
        end

        it 'queues domain tests' do
          allow(ServiceConfiguration).to receive(:active?).with("domain_testing").and_return(true)
          expect(DomainDnsTestingWorker).to receive(:perform_async)

          service.execute
        end
      end

      context 'when domain exists without company' do
        let!(:existing_domain) { create(:domain, domain: 'example.com', company: nil) }

        it 'associates existing domain with company' do
          expect { service.execute }.not_to change(Domain, :count)

          result = service.execute
          expect(result).to be_success
          expect(existing_domain.reload.company).to eq(company)
        end
      end

      context 'when company already has a domain' do
        let!(:existing_domain) { create(:domain, domain: 'old-domain.com', company: company, dns: true, mx: false, www: true) }

        it 'updates the existing domain' do
          expect { service.execute }.not_to change(Domain, :count)

          result = service.execute
          expect(result).to be_success

          domain = result.data[:domain]
          expect(domain.id).to eq(existing_domain.id)
          expect(domain.domain).to eq('example.com')
        end

        it 'resets test results when domain changes' do
          service.execute

          existing_domain.reload
          expect(existing_domain.dns).to be_nil
          expect(existing_domain.mx).to be_nil
          expect(existing_domain.www).to be_nil
          expect(existing_domain.a_record_ip).to be_nil
          expect(existing_domain.mx_error).to be_nil
        end
      end
    end

    context 'with domain normalization' do
      [
        { input: 'https://example.com', expected: 'example.com' },
        { input: 'http://example.com', expected: 'example.com' },
        { input: 'www.example.com', expected: 'example.com' },
        { input: 'https://www.example.com', expected: 'example.com' },
        { input: 'example.com/path/to/page', expected: 'example.com' },
        { input: 'example.com?query=param', expected: 'example.com' },
        { input: 'example.com:8080', expected: 'example.com' },
        { input: 'EXAMPLE.COM', expected: 'example.com' },
        { input: '  example.com  ', expected: 'example.com' }
      ].each do |test_case|
        it "normalizes #{test_case[:input]} to #{test_case[:expected]}" do
          service = described_class.new(company, test_case[:input])
          result = service.execute

          expect(result).to be_success
          expect(result.data[:domain].domain).to eq(test_case[:expected])
        end
      end
    end

    context 'with domain validation' do
      [
        'example',
        '.com',
        'example.',
        '.example.com',
        'example..com',
        '',
        'https://',
        'http:///'
      ].each do |invalid_domain|
        it "rejects invalid domain: #{invalid_domain}" do
          service = described_class.new(company, invalid_domain)
          result = service.execute

          expect(result).to be_error
          expect(result.error_message).to include('Invalid domain format')
        end
      end
    end

    context 'when ServiceConfiguration is disabled' do
      let(:website_url) { 'example.com' }

      it 'does not queue domain tests' do
        allow(ServiceConfiguration).to receive(:active?).with("domain_testing").and_return(false)
        expect(DomainDnsTestingWorker).not_to receive(:perform_async)

        service.execute
      end
    end

    context 'with error handling' do
      let(:website_url) { 'example.com' }

      it 'handles database errors gracefully' do
        allow(Domain).to receive(:transaction).and_raise(ActiveRecord::RecordInvalid.new)

        result = service.execute
        expect(result).to be_error
        expect(result.error_message).to include('Failed to process domain')
      end
    end
  end
end
