# frozen_string_literal: true

class CompanyServiceQueueButtonComponent < ViewComponent::Base
  include ActionView::Helpers::NumberHelper

  def initialize(service_name:, title:, icon:, action_path:, queue_name:)
    @service_name = service_name
    @title = title
    @icon = icon
    @action_path = action_path
    @queue_name = queue_name
  end

  private

  attr_reader :service_name, :title, :icon, :action_path, :queue_name

  def companies_needing_service
    Company.needing_service(service_name).count
  end

  # For web discovery, show total potential companies that could be processed
  def web_discovery_potential
    return 0 unless service_name == "company_web_discovery"
    Company.web_discovery_potential.count
  end

  # For LinkedIn discovery, show total potential companies that could be processed
  def linkedin_discovery_potential
    return 0 unless service_name == "company_linkedin_discovery"
    Company.linkedin_discovery_potential.count
  end

  # Calculate companies that have been successfully processed for this service
  def companies_completed
    case service_name
    when "company_web_discovery"
      # Count companies that have actually been successfully processed by web discovery service
      ServiceAuditLog
        .joins("JOIN companies ON companies.id = CAST(service_audit_logs.record_id AS INTEGER)")
        .where(service_name: "company_web_discovery", status: "success")
        .where("companies.operating_revenue > ?", 10_000_000)
        .where("companies.website IS NULL OR companies.website = ''")
        .count
    when "company_financial_data"
      # Count companies that have actually been successfully processed by financial data service
      ServiceAuditLog
        .joins("JOIN companies ON companies.id = CAST(service_audit_logs.record_id AS INTEGER)")
        .where(service_name: "company_financial_data", status: "success")
        .where("companies.source_country = 'NO'")
        .where("companies.source_registry = 'brreg'") 
        .where("companies.ordinary_result IS NULL")
        .where("companies.organization_form_code IN ('AS', 'ASA', 'DA', 'ANS')")
        .count
    when "company_linkedin_discovery"
      # Count companies that have actually been successfully processed by LinkedIn discovery service
      ServiceAuditLog
        .joins("JOIN companies ON companies.id = CAST(service_audit_logs.record_id AS INTEGER)")
        .where(service_name: "company_linkedin_discovery", status: "success")
        .where("companies.operating_revenue > ?", 10_000_000)
        .count
    else
      0
    end
  end

  # Calculate completion percentage
  def completion_percentage
    total = case service_name
    when "company_web_discovery"
      web_discovery_potential
    when "company_financial_data"
      Company.needs_financial_update.count
    when "company_linkedin_discovery"
      linkedin_discovery_potential
    else
      return 0
    end
    
    return 0 if total == 0
    
    completed = companies_completed
    percentage = (completed.to_f / total.to_f) * 100
    
    # Round to 1 decimal place for small percentages, 0 decimals for large ones
    if percentage < 1
      percentage.round(1)
    else
      percentage.round
    end
  end

  # Check if this is the web discovery service
  def web_discovery_service?
    service_name == "company_web_discovery"
  end

  # Check if this is the financial data service
  def financial_data_service?
    service_name == "company_financial_data"
  end

  # Check if this is the LinkedIn discovery service
  def linkedin_discovery_service?
    service_name == "company_linkedin_discovery"
  end

  # Check if this service should show completion percentage
  def show_completion_percentage?
    web_discovery_service? || financial_data_service? || linkedin_discovery_service?
  end

  def queue_depth
    Sidekiq::Queue.new(queue_name).size
  end

  def button_classes
    # Flowbite primary button classes
    "text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
  end

  def card_classes
    # Flowbite card classes
    "p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
  end

  def input_classes
    # Flowbite form input classes
    "bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
  end

  def label_classes
    # Flowbite label classes
    "block mb-2 text-sm font-medium text-gray-900 dark:text-white"
  end

  def text_muted_classes
    # Muted text classes
    "text-sm text-gray-600 dark:text-gray-400"
  end

  def heading_classes
    # Heading classes
    "mb-2 text-lg font-semibold text-gray-900 dark:text-white"
  end
end
