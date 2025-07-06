# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompanySearchAutocompleteComponent, type: :component do
  let(:component) { described_class.new }

  describe "rendering" do
    subject { render_inline(component) }

    it "renders the autocomplete container" do
      expect(subject.css('div[data-controller="company-search-autocomplete"]')).to be_present
    end

    it "renders the input field with default attributes" do
      input = subject.css('input[type="text"]').first
      
      expect(input).to be_present
      expect(input['name']).to eq('search')
      expect(input['id']).to eq('company-search')
      expect(input['placeholder']).to eq('Search companies...')
      expect(input['autocomplete']).to eq('off')
    end

    it "renders the dropdown container" do
      dropdown = subject.css('div[data-company-search-autocomplete-target="dropdown"]').first
      
      expect(dropdown).to be_present
      expect(dropdown['class']).to include('hidden') # Initially hidden
    end

    it "includes stimulus data attributes" do
      container = subject.css('div[data-controller="company-search-autocomplete"]').first
      
      expect(container['data-company-search-autocomplete-url-value']).to be_present
      expect(container['data-company-search-autocomplete-min-characters-value']).to eq('2')
      expect(container['data-company-search-autocomplete-debounce-delay-value']).to eq('300')
      expect(container['data-company-search-autocomplete-max-suggestions-value']).to eq('10')
    end

    it "includes input stimulus targets and actions" do
      input = subject.css('input[type="text"]').first
      
      expect(input['data-company-search-autocomplete-target']).to eq('input')
      expect(input['data-action']).to eq('input->company-search-autocomplete#onInput')
    end
  end

  describe "with custom parameters" do
    let(:component) do
      described_class.new(
        current_search: "Test Company",
        placeholder: "Custom placeholder",
        name: "custom_search",
        id: "custom-id"
      )
    end

    subject { render_inline(component) }

    it "uses custom search value" do
      input = subject.css('input[type="text"]').first
      expect(input['value']).to eq('Test Company')
    end

    it "uses custom placeholder" do
      input = subject.css('input[type="text"]').first
      expect(input['placeholder']).to eq('Custom placeholder')
    end

    it "uses custom name" do
      input = subject.css('input[type="text"]').first
      expect(input['name']).to eq('custom_search')
    end

    it "uses custom id" do
      input = subject.css('input[type="text"]').first
      expect(input['id']).to eq('custom-id')
    end
  end

  describe "CSS classes" do
    subject { render_inline(component) }

    it "applies default styling classes" do
      input = subject.css('input[type="text"]').first
      
      expect(input['class']).to include('w-full')
      expect(input['class']).to include('px-4')
      expect(input['class']).to include('py-2')
      expect(input['class']).to include('border')
      expect(input['class']).to include('rounded-lg')
      expect(input['class']).to include('focus:ring-2')
      expect(input['class']).to include('dark:bg-gray-700')
    end

    it "applies dropdown styling classes" do
      dropdown = subject.css('div[data-company-search-autocomplete-target="dropdown"]').first
      
      expect(dropdown['class']).to include('absolute')
      expect(dropdown['class']).to include('z-50')
      expect(dropdown['class']).to include('bg-white')
      expect(dropdown['class']).to include('dark:bg-gray-800')
      expect(dropdown['class']).to include('border')
      expect(dropdown['class']).to include('rounded-lg')
      expect(dropdown['class']).to include('shadow-lg')
      expect(dropdown['class']).to include('hidden')
    end
  end

  describe "custom CSS classes" do
    let(:component) do
      described_class.new(css_classes: "custom-class another-class")
    end

    subject { render_inline(component) }

    it "uses custom CSS classes" do
      input = subject.css('input[type="text"]').first
      expect(input['class']).to eq('custom-class another-class')
    end
  end
end