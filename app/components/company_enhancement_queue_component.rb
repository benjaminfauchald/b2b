# frozen_string_literal: true

class CompanyEnhancementQueueComponent < ViewComponent::Base
  def initialize(queue_stats: {})
    @queue_stats = queue_stats
  end

  private

  attr_reader :queue_stats

  def services
    [
      {
        name: "Financial Data",
        service_name: "company_financial_data",
        queue_name: "company_financial_data",
        path: queue_financial_data_companies_path,
        icon: "currency-dollar",
        color: "blue",
        description: "Fetch revenue, profit, and financial metrics"
      },
      {
        name: "Web Discovery",
        service_name: "company_web_discovery",
        queue_name: "company_web_discovery",
        path: queue_web_discovery_companies_path,
        icon: "globe-alt",
        color: "green",
        description: "Discover company web pages and online presence"
      },
      {
        name: "LinkedIn Discovery",
        service_name: "company_linkedin_discovery",
        queue_name: "company_linkedin_discovery",
        path: queue_linkedin_discovery_companies_path,
        icon: "user-group",
        color: "indigo",
        description: "Find company LinkedIn profiles"
      },
      {
        name: "Employee Discovery",
        service_name: "company_employee_discovery",
        queue_name: "company_employee_discovery",
        path: queue_employee_discovery_companies_path,
        icon: "users",
        color: "purple",
        description: "Discover employee information"
      }
    ]
  end

  def companies_needing_service(service_name)
    Company.needing_service(service_name).count
  end

  def queue_size(queue_name)
    queue_stats[queue_name] || 0
  end

  def total_queued
    services.sum { |s| queue_size(s[:queue_name]) }
  end

  def workers_busy
    queue_stats[:workers_busy] || 0
  end

  def total_processed
    queue_stats[:total_processed] || 0
  end

  def total_failed
    queue_stats[:total_failed] || 0
  end
end
