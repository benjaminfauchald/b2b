# frozen_string_literal: true

class CompanyEnhancementStatusComponent < ViewComponent::Base
  def initialize(company:)
    @company = company
  end

  private

  attr_reader :company

  def services
    [
      {
        name: "Financial Data",
        service_name: "company_financial_data",
        icon: "currency-dollar",
        last_updated: company.last_financial_update_at,
        has_data: company.operating_revenue.present? || company.annual_result.present?,
        data_summary: financial_data_summary,
        color: "blue"
      },
      {
        name: "Web Discovery",
        service_name: "company_web_discovery",
        icon: "globe-alt",
        last_updated: company.web_discovery_updated_at,
        has_data: company.web_pages.present?,
        data_summary: web_pages_summary,
        color: "green"
      },
      {
        name: "LinkedIn Profile",
        service_name: "company_linkedin_discovery",
        icon: "user-group",
        last_updated: company.linkedin_last_processed_at,
        has_data: company.linkedin_url.present?,
        data_summary: linkedin_summary,
        color: "indigo"
      },
      {
        name: "Employee Discovery",
        service_name: "company_employee_discovery",
        icon: "users",
        last_updated: company.employee_discovery_updated_at,
        has_data: company.employees_data.present?,
        data_summary: employees_summary,
        color: "purple"
      }
    ]
  end

  def financial_data_summary
    return "No data" unless company.operating_revenue.present? || company.annual_result.present?

    parts = []
    if company.operating_revenue.present?
      parts << "Revenue: #{number_to_currency(company.operating_revenue, unit: 'NOK', precision: 0)}"
    end
    if company.annual_result.present?
      parts << "Result: #{number_to_currency(company.annual_result, unit: 'NOK', precision: 0)}"
    end
    parts.any? ? parts.join(" • ") : "Financial data available"
  end

  def web_pages_summary
    return "No data" unless company.web_pages.present?

    begin
      # Parse JSON if it's a string, or use directly if it's already parsed
      parsed_pages = company.web_pages.is_a?(String) ? JSON.parse(company.web_pages) : company.web_pages
      
      # Handle different possible structures
      if parsed_pages.is_a?(Array)
        "#{parsed_pages.size} pages found"
      elsif parsed_pages.is_a?(Hash) && parsed_pages["pages"]
        pages = parsed_pages["pages"]
        "#{pages.size} pages found"
      elsif parsed_pages.is_a?(Hash)
        # If it's a hash but no "pages" key, count the hash entries
        "#{parsed_pages.keys.size} items found"
      else
        "Web pages data available"
      end
    rescue JSON::ParserError
      "Web pages data available (format error)"
    end
  end

  def linkedin_summary
    return "No data" unless company.linkedin_url.present?

    "Profile found"
  end

  def employees_summary
    return "No data" unless company.employees_data.present?

    begin
      # Parse JSON if it's a string, or use directly if it's already parsed
      parsed_employees = company.employees_data.is_a?(String) ? JSON.parse(company.employees_data) : company.employees_data
      
      # Handle different possible structures
      if parsed_employees.is_a?(Array)
        "#{parsed_employees.size} employees found"
      elsif parsed_employees.is_a?(Hash) && parsed_employees["employees"]
        employees = parsed_employees["employees"]
        "#{employees.size} employees found"
      elsif parsed_employees.is_a?(Hash)
        # If it's a hash but no "employees" key, count the hash entries
        "#{parsed_employees.keys.size} items found"
      else
        "Employee data available"
      end
    rescue JSON::ParserError
      "Employee data available (format error)"
    end
  end

  def last_update_text(timestamp)
    return "Never" unless timestamp

    time_ago = time_ago_in_words(timestamp)
    "#{time_ago} ago"
  end

  def status_color(service)
    if service[:has_data]
      "text-green-600 dark:text-green-400"
    elsif service[:last_updated]
      "text-yellow-600 dark:text-yellow-400"
    else
      "text-gray-400 dark:text-gray-500"
    end
  end

  def status_icon(service)
    if service[:has_data]
      "check-circle"
    elsif service[:last_updated]
      "clock"
    else
      "x-circle"
    end
  end

  def queue_path(service_name)
    case service_name
    when "company_financial_data"
      queue_single_financial_data_company_path(company)
    when "company_web_discovery"
      queue_single_web_discovery_company_path(company)
    when "company_linkedin_discovery"
      queue_single_linkedin_discovery_company_path(company)
    when "company_employee_discovery"
      queue_single_employee_discovery_company_path(company)
    end
  end
end
