# frozen_string_literal: true

class CompanyServiceButtonComponent < ViewComponent::Base
  def initialize(company:, service:, size: :normal)
    @company = company
    @service = service.to_sym
    @size = size.to_sym
  end

  private

  attr_reader :company, :service, :size

  def service_config
    @service_config ||= {
      financial_data: {
        name: "Financial Data",
        service_name: "company_financial_data",
        column: :operating_revenue,
        action_path: ->(company) { queue_single_financial_data_company_path(company) },
        worker: "CompanyFinancialDataWorker",
        icon: financial_data_icon,
        last_updated_column: :last_financial_update_at
      },
      web_discovery: {
        name: "Web Discovery",
        service_name: "company_web_discovery",
        column: :web_pages,
        action_path: ->(company) { queue_single_web_discovery_company_path(company) },
        worker: "CompanyWebDiscoveryWorker",
        icon: web_discovery_icon,
        last_updated_column: :web_discovery_updated_at
      },
      linkedin_discovery: {
        name: "LinkedIn",
        service_name: "company_linkedin_discovery",
        column: :linkedin_url,
        action_path: ->(company) { queue_single_linkedin_discovery_company_path(company) },
        worker: "CompanyLinkedinDiscoveryWorker",
        icon: linkedin_icon,
        last_updated_column: :linkedin_last_processed_at
      }
    }[service]
  end

  def service_active?
    ServiceConfiguration.active?(service_config[:service_name])
  end

  def test_status
    value = company.send(service_config[:column])
    case value
    when nil
      :never_tested
    else
      :has_data
    end
  end

  def last_tested_time
    company.send(service_config[:last_updated_column])
  end

  def pending_test?
    # Check if the most recent audit log is pending
    most_recent_audit = company.service_audit_logs
                              .where(service_name: service_config[:service_name])
                              .where("created_at > ?", 10.minutes.ago)
                              .order(created_at: :desc)
                              .first

    # If we have a recent audit log, check if it's still pending
    if most_recent_audit
      return most_recent_audit.status == "pending"
    end

    # Otherwise check if job is queued
    job_queued?
  end

  def job_queued?
    # Check if company has a job queued in Sidekiq
    require "sidekiq/api"

    queue = Sidekiq::Queue.new("default")
    queue.any? do |job|
      job.klass == service_config[:worker] &&
      job.args.first == company.id
    end
  rescue => e
    Rails.logger.error "Error checking queue status: #{e.message}"
    false
  end

  def button_text
    case test_status
    when :never_tested
      "Fetch #{service_config[:name]}"
    when :has_data
      "Update #{service_config[:name]}"
    end
  end

  def button_classes
    base_classes = case size
    when :small
                    "px-3 py-1.5 text-xs"
    when :large
                    "px-6 py-3 text-base"
    else
                    "px-4 py-2 text-sm"
    end

    state_classes = if pending_test?
                     "bg-gray-400 hover:bg-gray-500 cursor-not-allowed"
    elsif !service_active?
                     "bg-gray-300 text-gray-500 cursor-not-allowed"
    else
                     case test_status
                     when :never_tested
                       "bg-blue-600 hover:bg-blue-700 text-white"
                     when :has_data
                       "bg-green-600 hover:bg-green-700 text-white"
                     end
    end

    "#{base_classes} #{state_classes} font-medium rounded-lg focus:ring-4 focus:outline-none transition-colors duration-200 flex items-center justify-center"
  end

  def button_disabled?
    pending_test? || !service_active?
  end

  def action_path
    service_config[:action_path].call(company)
  end

  def status_badge_classes
    case test_status
    when :never_tested
      "bg-gray-100 text-gray-800"
    when :has_data
      "bg-green-100 text-green-800"
    end
  end

  def status_text
    if pending_test?
      "Fetching..."
    else
      case test_status
      when :never_tested
        "No Data"
      when :has_data
        if service == :financial_data
          financial_summary
        else
          "Has Data"
        end
      end
    end
  end

  def financial_summary
    return "No Data" unless company.operating_revenue.present?

    parts = []
    parts << "Revenue: #{format_currency(company.operating_revenue)}" if company.operating_revenue.present?
    parts << "Costs: #{format_currency(company.operating_costs)}" if company.operating_costs.present?
    parts << "Ordinary: #{format_currency(company.ordinary_result)}" if company.ordinary_result.present?
    parts << "Annual: #{format_currency(company.annual_result)}" if company.annual_result.present?

    parts.any? ? parts.join(" • ") : "Financial data available"
  end

  def format_currency(amount)
    return "N/A" unless amount

    if amount.abs >= 1_000_000
      "#{(amount / 1_000_000.0).round(1)}M NOK"
    elsif amount.abs >= 1_000
      "#{(amount / 1_000.0).round(0)}K NOK"
    else
      "#{amount} NOK"
    end
  end

  def form_id
    "queue-#{service}-#{company.id}"
  end

  def financial_data_icon
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>'.html_safe
  end

  def web_discovery_icon
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"></path>
    </svg>'.html_safe
  end

  def linkedin_icon
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
    </svg>'.html_safe
  end

  def spinner_icon
    '<svg class="animate-spin -ml-1 mr-3 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
    </svg>'.html_safe
  end
end
