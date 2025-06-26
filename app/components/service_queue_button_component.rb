# frozen_string_literal: true

class ServiceQueueButtonComponent < ViewComponent::Base
  def initialize(service_name:, title:, icon:, action_path:, queue_name:)
    @service_name = service_name
    @title = title
    @icon = icon
    @action_path = action_path
    @queue_name = queue_name
  end

  private

  attr_reader :service_name, :title, :icon, :action_path, :queue_name

  def domains_needing_service
    Domain.needing_service(service_name).count
  end

  def queue_depth
    case queue_name
    when "DomainARecordTestingService"
      # A Record testing runs in the default queue as DomainARecordTestingWorker
      Sidekiq::Queue.new("default").count { |job| job.klass == "DomainARecordTestingWorker" }
    when "DomainWebContentExtractionWorker"
      # Web content extraction runs in the default queue
      Sidekiq::Queue.new("default").count { |job| job.klass == "DomainWebContentExtractionWorker" }
    else
      Sidekiq::Queue.new(queue_name).size
    end
  rescue StandardError
    0
  end

  def domains_tested_successfully
    case service_name
    when "domain_testing"
      Domain.dns_active.count
    when "domain_mx_testing"
      Domain.with_mx.count
    when "domain_a_record_testing"
      Domain.www_active.count
    when "domain_web_content_extraction"
      Domain.with_web_content.count
    else
      0
    end
  end

  def domains_tested_invalid
    case service_name
    when "domain_testing"
      Domain.dns_inactive.count
    when "domain_mx_testing"
      Domain.dns_active.where(mx: false).count
    when "domain_a_record_testing"
      Domain.dns_active.www_inactive.count
    when "domain_web_content_extraction"
      Domain.with_a_record.where(web_content_data: nil).joins(:service_audit_logs)
            .where(service_audit_logs: { service_name: "domain_web_content_extraction", status: "failed" }).distinct.count
    else
      0
    end
  end

  def total_domains_for_service
    case service_name
    when "domain_testing"
      Domain.count
    when "domain_mx_testing"
      Domain.dns_active.count
    when "domain_a_record_testing"
      Domain.dns_active.count
    when "domain_web_content_extraction"
      Domain.with_a_record.count
    else
      Domain.count
    end
  end

  def success_percentage
    total = total_domains_for_service
    return 0 if total.zero?
    
    successful = domains_tested_successfully
    ((successful.to_f / total) * 100).round(1)
  end

  def tested_domains_count
    domains_tested_successfully + domains_tested_invalid
  end

  def completion_percentage
    total = total_domains_for_service
    return 0 if total.zero?
    
    tested = tested_domains_count
    ((tested.to_f / total) * 100).round(1)
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
