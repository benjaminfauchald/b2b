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
        last_updated: company.financial_data_updated_at,
        has_data: company.revenue.present?,
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
    return "No data" unless company.revenue.present?
    
    parts = []
    parts << "Revenue: #{number_to_currency(company.revenue, unit: 'NOK', precision: 0)}" if company.revenue
    parts << "Year: #{company.year}" if company.year
    parts.join(" • ")
  end

  def web_pages_summary
    return "No data" unless company.web_pages.present?
    
    pages = company.web_pages["pages"] || []
    "#{pages.size} pages found"
  end

  def linkedin_summary
    return "No data" unless company.linkedin_url.present?
    
    "Profile found"
  end

  def employees_summary
    return "No data" unless company.employees_data.present?
    
    employees = company.employees_data["employees"] || []
    "#{employees.size} employees found"
  end

  def last_update_text(timestamp)
    return "Never" unless timestamp
    
    time_ago = time_ago_in_words(timestamp)
    "#{time_ago} ago"
  end

  def status_color(service)
    if service[:has_data]
      "text-green-600"
    elsif service[:last_updated]
      "text-yellow-600"
    else
      "text-gray-400"
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