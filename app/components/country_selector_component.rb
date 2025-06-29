class CountrySelectorComponent < ViewComponent::Base
  attr_reader :available_countries, :selected_country

  def initialize(available_countries:, selected_country:)
    @available_countries = available_countries
    @selected_country = selected_country
  end

  def country_name(code)
    COUNTRY_NAMES[code] || code
  end

  def country_flag(code)
    COUNTRY_FLAGS[code] || "🏳️"
  end

  private

  COUNTRY_NAMES = {
    "NO" => "Norway",
    "SE" => "Sweden",
    "DK" => "Denmark",
    "FI" => "Finland",
    "IS" => "Iceland",
    "DE" => "Germany",
    "GB" => "United Kingdom",
    "US" => "United States",
    "NL" => "Netherlands",
    "FR" => "France",
    "ES" => "Spain",
    "IT" => "Italy"
  }.freeze

  COUNTRY_FLAGS = {
    "NO" => "🇳🇴",
    "SE" => "🇸🇪",
    "DK" => "🇩🇰",
    "FI" => "🇫🇮",
    "IS" => "🇮🇸",
    "DE" => "🇩🇪",
    "GB" => "🇬🇧",
    "US" => "🇺🇸",
    "NL" => "🇳🇱",
    "FR" => "🇫🇷",
    "ES" => "🇪🇸",
    "IT" => "🇮🇹"
  }.freeze
end
