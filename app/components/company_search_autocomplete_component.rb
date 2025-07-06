# frozen_string_literal: true

# ============================================================================
# Company Search Autocomplete Component
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/company_search_autocomplete.rb
# ============================================================================

class CompanySearchAutocompleteComponent < ViewComponent::Base
  def initialize(current_search: nil, placeholder: "Search companies...", name: "search", id: "company-search", css_classes: nil)
    @current_search = current_search
    @placeholder = placeholder
    @name = name
    @id = id
    @css_classes = css_classes || default_css_classes
  end

  private

  attr_reader :current_search, :placeholder, :name, :id, :css_classes

  def autocomplete_url
    Rails.application.routes.url_helpers.search_suggestions_companies_path
  end

  def controller_data_attributes
    {
      controller: "company-search-autocomplete",
      company_search_autocomplete_url_value: autocomplete_url,
      company_search_autocomplete_min_characters_value: 2,
      company_search_autocomplete_debounce_delay_value: 300,
      company_search_autocomplete_max_suggestions_value: 10
    }
  end

  def input_data_attributes
    {
      company_search_autocomplete_target: "input",
      action: "input->company-search-autocomplete#onInput"
    }
  end

  def dropdown_css_classes
    [
      "absolute", "top-full", "left-0", "right-0", "z-50",
      "bg-white", "dark:bg-gray-800",
      "border", "border-gray-300", "dark:border-gray-600",
      "rounded-lg", "shadow-lg",
      "mt-1", "max-h-60", "overflow-y-auto",
      "hidden" # Initially hidden
    ].join(" ")
  end

  def default_css_classes
    [
      "w-full", "px-4", "py-2",
      "border", "border-gray-300", "dark:border-gray-600",
      "rounded-lg",
      "bg-white", "dark:bg-gray-700",
      "text-gray-900", "dark:text-white",
      "placeholder-gray-500", "dark:placeholder-gray-400",
      "focus:ring-2", "focus:ring-blue-500", "focus:border-blue-500",
      "dark:focus:ring-blue-400", "dark:focus:border-blue-400"
    ].join(" ")
  end
end