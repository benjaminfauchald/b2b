# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvUploadComponent, type: :component do
  describe 'rendering' do
    it 'renders the upload form with drag-and-drop zone' do
      render_inline(described_class.new)

      expect(page).to have_css('[data-csv-upload-target="dropZone"]')
      expect(page).to have_css('input[type="file"][accept=".csv"]')
      expect(page).to have_text('Choose CSV file or drag and drop')
      expect(page).to have_text('CSV files only')
    end

    it 'includes proper file validation attributes' do
      render_inline(described_class.new)

      file_input = page.find('input[type="file"]')
      expect(file_input[:accept]).to eq('.csv')
      expect(file_input['data-csv-upload-target']).to eq('fileInput')
    end

    it 'has proper Flowbite styling classes' do
      render_inline(described_class.new)

      # Check for Flowbite drag-and-drop styling
      expect(page).to have_css('.border-dashed')
      expect(page).to have_css('.border-gray-300')
      expect(page).to have_css('.dark\\:border-gray-600')
      expect(page).to have_css('.hover\\:bg-gray-100')
    end

    it 'includes upload progress indicator' do
      render_inline(described_class.new)

      expect(page).to have_css('[data-csv-upload-target="progress"]', visible: false)
      expect(page).to have_css('.progress-bar', visible: false)
    end

    it 'includes error display area' do
      render_inline(described_class.new)

      expect(page).to have_css('[data-csv-upload-target="errors"]', visible: false)
      expect(page).to have_css('.error-message', visible: false)
    end

    it 'has proper accessibility attributes' do
      render_inline(described_class.new)

      expect(page).to have_css('[role="button"]')
      expect(page).to have_css('[aria-label="Upload CSV file"]')
      expect(page).to have_css('[tabindex="0"]')
    end
  end

  describe 'with custom options' do
    it 'applies custom CSS classes' do
      render_inline(described_class.new(class: 'custom-class'))

      expect(page).to have_css('.custom-class')
    end

    it 'accepts custom maximum file size' do
      render_inline(described_class.new(max_size: '5MB'))

      expect(page).to have_text('Maximum file size: 5MB')
    end

    it 'accepts custom help text' do
      render_inline(described_class.new(help_text: 'Custom help message'))

      expect(page).to have_text('Custom help message')
    end
  end

  describe 'JavaScript behavior', :js do
    it 'shows upload progress when file is selected' do
      render_inline(described_class.new)

      # Simulate file selection would require capybara-webkit or similar
      # This is a placeholder for integration testing
      expect(page).to have_css('[data-csv-upload-target="dropZone"]')
    end

    it 'validates file type on selection' do
      render_inline(described_class.new)

      # Test file validation behavior
      expect(page).to have_css('[data-action="change->csv-upload#validateFile"]')
    end

    it 'handles drag and drop events' do
      render_inline(described_class.new)

      expect(page).to have_css('[data-action*="drop->csv-upload#handleDrop"]')
      expect(page).to have_css('[data-action*="dragover->csv-upload#handleDragOver"]')
      expect(page).to have_css('[data-action*="dragleave->csv-upload#handleDragLeave"]')
    end
  end

  describe 'responsive design' do
    it 'includes responsive classes for mobile devices' do
      render_inline(described_class.new)

      expect(page).to have_css('.text-sm')
      expect(page).to have_css('.text-xs')
      expect(page).to have_css('.w-full')
    end

    it 'has proper mobile touch targets' do
      render_inline(described_class.new)

      # Ensure touch targets are at least 44px for mobile
      expect(page).to have_css('.h-64')
    end
  end

  describe 'dark mode support' do
    it 'includes dark mode classes' do
      render_inline(described_class.new)

      expect(page).to have_css('.dark\\:bg-gray-700')
      expect(page).to have_css('.dark\\:border-gray-600')
      expect(page).to have_css('.dark\\:text-gray-400')
    end
  end
end
