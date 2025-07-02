require 'rails_helper'

RSpec.describe DomainTestStatusComponent, type: :component do
  let(:domain) { create(:domain) }
  let(:component) { described_class.new(domain: domain) }
  let(:rendered) { render_inline(component) }

  describe '#render?' do
    context 'with domain present' do
      it 'renders the component' do
        expect(component.render?).to be true
      end
    end

    context 'with domain nil' do
      let(:domain) { nil }

      it 'does not render the component' do
        expect(component.render?).to be false
      end
    end
  end

  describe 'test status badges' do
    context 'when all tests are pending' do
      let(:domain) { create(:domain, dns: nil, mx: nil, www: nil) }

      it 'shows testing status for all tests' do
        expect(rendered).to have_css('span', text: 'DNS')
        expect(rendered).to have_css('span', text: 'MX')
        expect(rendered).to have_css('span', text: 'A Record')
        expect(rendered).to have_css('.animate-pulse', count: 3)
      end

      it 'enables polling' do
        expect(rendered).to have_css('[data-domain-test-status-testing-value="true"]')
      end
    end

    context 'when DNS test is successful' do
      let(:domain) { create(:domain, dns: true, mx: nil, www: nil) }

      it 'shows success for DNS and testing for others' do
        expect(rendered).to have_css('.bg-green-100', text: 'DNS')
        expect(rendered).to have_css('.animate-pulse', text: 'MX')
        expect(rendered).to have_css('.animate-pulse', text: 'A Record')
      end

      it 'enables polling' do
        expect(rendered).to have_css('[data-domain-test-status-testing-value="true"]')
      end
    end

    context 'when DNS test failed' do
      let(:domain) { create(:domain, dns: false, mx: nil, www: nil) }

      it 'shows error for DNS and skipped for others' do
        expect(rendered).to have_css('.bg-red-100', text: 'DNS')
        expect(rendered).to have_css('.bg-gray-100.text-gray-500', text: 'MX')
        expect(rendered).to have_css('.bg-gray-100.text-gray-500', text: 'A Record')
      end

      it 'disables polling' do
        expect(rendered).to have_css('[data-domain-test-status-testing-value="false"]')
      end
    end

    context 'when all tests are complete' do
      let(:domain) { create(:domain, dns: true, mx: true, www: false) }

      it 'shows correct status for each test' do
        expect(rendered).to have_css('.bg-green-100', text: 'DNS')
        expect(rendered).to have_css('.bg-green-100', text: 'MX')
        expect(rendered).to have_css('.bg-red-100', text: 'A Record')
      end

      it 'disables polling' do
        expect(rendered).to have_css('[data-domain-test-status-testing-value="false"]')
      end
    end

    context 'with mixed results' do
      let(:domain) { create(:domain, dns: true, mx: false, www: true) }

      it 'shows mixed status badges' do
        expect(rendered).to have_css('.bg-green-100', text: 'DNS')
        expect(rendered).to have_css('.bg-red-100', text: 'MX')
        expect(rendered).to have_css('.bg-green-100', text: 'A Record')
      end
    end
  end

  describe 'stimulus controller attributes' do
    let(:domain) { create(:domain, id: 123) }

    it 'sets correct data attributes' do
      expect(rendered).to have_css('[data-controller="domain-test-status"]')
      expect(rendered).to have_css('[data-domain-test-status-domain-id-value="123"]')
      expect(rendered).to have_css('[data-domain-test-status-refresh-interval-value="1000"]')
    end

    it 'has correct element ID' do
      expect(rendered).to have_css('#domain-test-status-123')
    end
  end

  describe 'dark mode support' do
    let(:domain) { create(:domain, dns: true, mx: false, www: nil) }

    it 'includes dark mode classes' do
      expect(rendered).to have_css('.dark\\:bg-green-900')
      expect(rendered).to have_css('.dark\\:text-green-300')
      expect(rendered).to have_css('.dark\\:bg-red-900')
      expect(rendered).to have_css('.dark\\:text-red-300')
    end
  end
end
