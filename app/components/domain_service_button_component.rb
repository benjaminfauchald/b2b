# frozen_string_literal: true

class DomainServiceButtonComponent < ViewComponent::Base
  def initialize(domain:, service:, size: :normal)
    @domain = domain
    @service = service.to_sym
    @size = size.to_sym
  end

  private

  attr_reader :domain, :service, :size

  def service_config
    @service_config ||= {
      dns: {
        name: "DNS",
        service_name: "domain_testing",
        column: :dns,
        action_path: ->(domain) { queue_single_dns_domain_path(domain) },
        worker: "DomainDnsTestingWorker",
        icon: dns_icon
      },
      mx: {
        name: "MX",
        service_name: "domain_mx_testing",
        column: :mx,
        action_path: ->(domain) { queue_single_mx_domain_path(domain) },
        worker: "DomainMxTestingWorker",
        icon: mx_icon
      },
      www: {
        name: "WWW",
        service_name: "domain_a_record_testing",
        column: :www,
        action_path: ->(domain) { queue_single_www_domain_path(domain) },
        worker: "DomainARecordTestingWorker",
        icon: www_icon
      }
    }[service]
  end

  def service_active?
    ServiceConfiguration.active?(service_config[:service_name])
  end

  def test_status
    value = domain.send(service_config[:column])
    case value
    when nil
      :never_tested
    when true
      :passed
    when false
      :failed
    end
  end

  def last_tested_time
    # Get the last successful service run for this domain and service
    last_run = domain.service_audit_logs
                    .where(service_name: service_config[:service_name])
                    .where(status: "success")
                    .order(completed_at: :desc)
                    .first

    last_run&.completed_at
  end

  def pending_test?
    # Check if the most recent audit log is pending
    most_recent_audit = domain.service_audit_logs
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
    # Check if domain has a job queued in Sidekiq
    require "sidekiq/api"

    queue = Sidekiq::Queue.new("default")
    queue.any? do |job|
      job.klass == service_config[:worker] &&
      job.args.first == domain.id
    end
  rescue => e
    Rails.logger.error "Error checking queue status: #{e.message}"
    false
  end

  def button_text
    case test_status
    when :never_tested
      "Test #{service_config[:name]}"
    when :passed
      "Re-test #{service_config[:name]}"
    when :failed
      "Retry #{service_config[:name]}"
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
                     when :passed
                       "bg-green-600 hover:bg-green-700 text-white"
                     when :failed
                       "bg-orange-600 hover:bg-orange-700 text-white"
                     end
    end

    "#{base_classes} #{state_classes} font-medium rounded-lg focus:ring-4 focus:outline-none transition-colors duration-200 flex items-center justify-center"
  end

  def button_disabled?
    pending_test? || !service_active?
  end

  def action_path
    service_config[:action_path].call(domain)
  end

  def status_badge_classes
    case test_status
    when :never_tested
      "bg-gray-100 text-gray-800"
    when :passed
      "bg-green-100 text-green-800"
    when :failed
      "bg-red-100 text-red-800"
    end
  end

  def status_text
    if pending_test?
      "Testing..."
    else
      case test_status
      when :never_tested
        "Not Tested"
      when :passed
        "Active"
      when :failed
        "Inactive"
      end
    end
  end

  def form_id
    "queue-#{service}-#{domain.id}"
  end

  def dns_icon
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
    </svg>'.html_safe
  end

  def mx_icon
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path>
    </svg>'.html_safe
  end

  def www_icon
    '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"></path>
    </svg>'.html_safe
  end

  def spinner_icon
    '<svg class="animate-spin -ml-1 mr-3 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
    </svg>'.html_safe
  end
end
