# frozen_string_literal: true

class CompanyRowComponent < ViewComponent::Base
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::DateHelper

  def initialize(company:, index: nil)
    @company = company
    @index = index
  end

  private

  attr_reader :company, :index

  def industry_display
    return "Not specified" unless company.primary_industry_description.present?

    # Truncate long industry names
    industry = company.primary_industry_description
    industry.length > 40 ? "#{industry[0..37]}..." : industry
  end

  def employee_count_display
    return "Not available" unless company.employee_count.present?

    number_with_delimiter(company.employee_count)
  end

  def website_display
    return nil unless company.website.present?

    # Clean up the URL for display
    url = company.website.gsub(/^https?:\/\//, "").gsub(/^www\./, "")
    url.length > 30 ? "#{url[0..27]}..." : url
  end

  def linkedin_display
    return nil unless company.linkedin_url.present? || company.linkedin_ai_url.present?

    # Prefer linkedin_url over linkedin_ai_url
    url = company.linkedin_url.present? ? company.linkedin_url : company.linkedin_ai_url

    # Extract company name from LinkedIn URL
    if url.match(/\/company\/([^\/\?]+)/)
      company_slug = $1
      # Truncate if too long to fit with confidence score
      if company_slug.length > 20
        "linkedin.com/#{company_slug[0..17]}..."
      else
        "linkedin.com/#{company_slug}"
      end
    else
      "LinkedIn Profile"
    end
  end

  def linkedin_confidence_badge
    return nil unless company.linkedin_ai_url.present? && company.linkedin_ai_confidence.present?

    confidence = company.linkedin_ai_confidence
    if confidence >= 80
      { text: "#{confidence}%", color: "green" }
    elsif confidence >= 60
      { text: "#{confidence}%", color: "yellow" }
    else
      { text: "#{confidence}%", color: "red" }
    end
  end

  def is_ai_linkedin?
    company.linkedin_ai_url.present? && company.linkedin_url.blank?
  end

  def row_background_class
    return "" unless index

    if index.even?
      "bg-gray-50 dark:bg-gray-800/50"
    else
      "bg-white dark:bg-gray-900"
    end
  end

  def revenue_display
    return nil unless company.operating_revenue.present?

    if company.operating_revenue >= 1_000_000_000
      "#{(company.operating_revenue / 1_000_000_000.0).round(1)}B NOK"
    elsif company.operating_revenue >= 1_000_000
      "#{(company.operating_revenue / 1_000_000.0).round(1)}M NOK"
    elsif company.operating_revenue >= 1_000
      "#{(company.operating_revenue / 1_000.0).round(0)}K NOK"
    else
      "#{number_with_delimiter(company.operating_revenue)} NOK"
    end
  end
end
