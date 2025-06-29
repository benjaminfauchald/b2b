# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportResultsComponent, type: :component do
  let(:successful_result) do
    double(
      'ImportResult',
      success?: true,
      imported_count: 5,
      failed_count: 0,
      total_count: 5,
      imported_domains: [
        { domain: 'example.com', row: 2 },
        { domain: 'test.org', row: 3 }
      ],
      failed_domains: [],
      processing_time: 2.5,
      summary_message: '5 domains imported successfully',
      domains_per_second: 2.0,
      has_csv_errors?: false,
      csv_errors: [],
      duplicate_count: 0
    )
  end

  let(:mixed_result) do
    double(
      'ImportResult',
      success?: false,
      imported_count: 3,
      failed_count: 2,
      total_count: 5,
      imported_domains: [
        { domain: 'example.com', row: 2 },
        { domain: 'test.org', row: 3 },
        { domain: 'valid.com', row: 5 }
      ],
      failed_domains: [
        { domain: '', row: 4, errors: [ "Domain can't be blank" ] },
        { domain: 'invalid..domain', row: 6, errors: [ 'Domain is invalid' ] }
      ],
      processing_time: 3.2,
      summary_message: '3 domains imported, 2 failed',
      domains_per_second: 1.6,
      has_csv_errors?: false,
      csv_errors: [],
      duplicate_count: 0
    )
  end

  let(:failed_result) do
    double(
      'ImportResult',
      success?: false,
      imported_count: 0,
      failed_count: 5,
      total_count: 5,
      imported_domains: [],
      failed_domains: [
        { domain: 'duplicate.com', row: 2, errors: [ 'Domain has already been taken' ] }
      ],
      processing_time: 1.1,
      error_message: 'Multiple validation errors occurred',
      summary_message: 'Import failed - 5 domains failed validation',
      domains_per_second: 4.5,
      has_csv_errors?: false,
      csv_errors: [],
      duplicate_count: 0
    )
  end

  describe 'successful import display' do
    it 'shows success summary with correct metrics' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_css('.bg-green-50')
      expect(page).to have_css('.text-green-700')
      expect(page).to have_text('Import Successful!')
      expect(page).to have_text('5 domains imported successfully')
      expect(page).to have_text('Processing time: 2.5 seconds')
    end

    it 'includes success icon' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_css('svg')
      expect(page).to have_css('.text-green-400')
    end

    it 'shows imported domains list' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_text('Imported Domains')
      expect(page).to have_text('example.com')
      expect(page).to have_text('test.org')
    end

    it 'includes action buttons' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_link('View All Domains')
      expect(page).to have_link('Import More Domains')
    end
  end

  describe 'mixed results display' do
    it 'shows partial success summary' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_css('.bg-yellow-50')
      expect(page).to have_css('.text-yellow-700')
      expect(page).to have_text('Import Completed with Errors')
      expect(page).to have_text('3 of 5 domains imported successfully')
      expect(page).to have_text('2 domains failed to import')
    end

    it 'shows both success and error sections' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_text('Successfully Imported (3)')
      expect(page).to have_text('Failed to Import (2)')
    end

    it 'displays detailed error information' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_text('Row 4')
      expect(page).to have_text("Domain can't be blank")
      expect(page).to have_text('Row 6: invalid..domain')
      expect(page).to have_text('Domain is invalid')
    end

    it 'includes download error report option' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_link('Download Error Report')
    end
  end

  describe 'failed import display' do
    it 'shows failure summary' do
      render_inline(described_class.new(result: failed_result))

      expect(page).to have_css('.bg-red-50')
      expect(page).to have_css('.text-red-700')
      expect(page).to have_text('Import Failed')
      expect(page).to have_text('0 domains imported')
      expect(page).to have_text('5 domains failed')
    end

    it 'includes error icon' do
      render_inline(described_class.new(result: failed_result))

      expect(page).to have_css('svg')
      expect(page).to have_css('.text-red-400')
    end

    it 'shows error message if present' do
      render_inline(described_class.new(result: failed_result))

      expect(page).to have_text('Multiple validation errors occurred')
    end

    it 'includes retry option' do
      render_inline(described_class.new(result: failed_result))

      expect(page).to have_link('Try Again')
    end
  end

  describe 'responsive design' do
    it 'includes responsive table classes' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_css('.overflow-x-auto')
      expect(page).to have_css('.sm\\:rounded-lg')
    end

    it 'has mobile-friendly error display' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_css('.block.sm\\:hidden') # Mobile view
      expect(page).to have_css('.hidden.sm\\:block') # Desktop view
    end
  end

  describe 'accessibility features' do
    it 'includes proper ARIA labels' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_css('[aria-label*="Import results"]')
      expect(page).to have_css('[role="status"]')
    end

    it 'has proper heading hierarchy' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_css('h2') # Main heading
      expect(page).to have_css('h3') # Section headings
    end

    it 'includes screen reader friendly text' do
      render_inline(described_class.new(result: mixed_result))

      expect(page).to have_css('.sr-only')
    end
  end

  describe 'dark mode support' do
    it 'includes dark mode classes' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_css('.dark\\:bg-gray-800')
      expect(page).to have_css('.dark\\:text-gray-200')
    end
  end

  describe 'performance metrics display' do
    it 'shows processing time' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_text('Processing time: 2.5 seconds')
    end

    it 'shows domains per second rate' do
      render_inline(described_class.new(result: successful_result))

      expect(page).to have_text('Rate: 2.0 domains/second')
    end
  end

  describe 'export functionality' do
    context 'with errors present' do
      it 'includes CSV export button for errors' do
        render_inline(described_class.new(result: mixed_result))

        expect(page).to have_button('Export Errors as CSV')
      end
    end

    context 'with successful imports' do
      it 'includes option to export imported domains' do
        render_inline(described_class.new(result: successful_result))

        expect(page).to have_button('Export Imported Domains')
      end
    end
  end
end
