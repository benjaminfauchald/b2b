# frozen_string_literal: true

class ImportResultsComponent < ViewComponent::Base
  def initialize(result:)
    @result = result
  end

  private

  attr_reader :result

  def status_alert_classes
    base_classes = "p-6 mb-6 rounded-lg border"

    case result_type
    when :success
      "#{base_classes} bg-green-50 border-green-200 dark:bg-green-900/20 dark:border-green-700"
    when :partial
      "#{base_classes} bg-yellow-50 border-yellow-200 dark:bg-yellow-900/20 dark:border-yellow-700"
    else
      "#{base_classes} bg-red-50 border-red-200 dark:bg-red-900/20 dark:border-red-700"
    end
  end

  def status_icon_classes
    base_classes = "w-6 h-6 mr-3"

    case result_type
    when :success
      "#{base_classes} text-green-400 dark:text-green-300"
    when :partial
      "#{base_classes} text-yellow-400 dark:text-yellow-300"
    else
      "#{base_classes} text-red-400 dark:text-red-300"
    end
  end

  def status_text_classes
    case result_type
    when :success
      "text-green-700 dark:text-green-200"
    when :partial
      "text-yellow-700 dark:text-yellow-200"
    else
      "text-red-700 dark:text-red-200"
    end
  end

  def status_heading_classes
    "text-lg font-semibold #{status_text_classes}"
  end

  def status_message_classes
    "mt-2 #{status_text_classes}"
  end

  def metrics_classes
    "mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4"
  end

  def metric_card_classes
    "p-3 bg-white dark:bg-gray-700 rounded-lg border border-gray-200 dark:border-gray-600"
  end

  def metric_label_classes
    "text-sm font-medium text-gray-600 dark:text-gray-400"
  end

  def metric_value_classes
    "text-lg font-bold text-gray-900 dark:text-white"
  end

  def section_heading_classes
    "text-lg font-semibold text-gray-900 dark:text-white mb-4"
  end

  def table_classes
    "min-w-full divide-y divide-gray-200 dark:divide-gray-700"
  end

  def table_header_classes
    "bg-gray-50 dark:bg-gray-700"
  end

  def table_header_cell_classes
    "px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider"
  end

  def table_body_classes
    "bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700"
  end

  def table_cell_classes
    "px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white"
  end

  def error_cell_classes
    "px-6 py-4 text-sm text-red-600 dark:text-red-400"
  end

  def button_classes(variant = :primary)
    base_classes = "inline-flex items-center px-4 py-2 border text-sm font-medium rounded-md transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2"

    case variant
    when :primary
      "#{base_classes} border-transparent text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-500"
    when :secondary
      "#{base_classes} border-gray-300 text-gray-700 bg-white hover:bg-gray-50 focus:ring-blue-500 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-600"
    else
      "#{base_classes} border-transparent text-blue-600 bg-blue-100 hover:bg-blue-200 focus:ring-blue-500 dark:bg-blue-900 dark:text-blue-300"
    end
  end

  def result_type
    @result_type ||= if result.success?
                       :success
    elsif result.imported_count > 0
                       :partial
    else
                       :failure
    end
  end

  def status_title
    case result_type
    when :success
      "Import Successful!"
    when :partial
      "Import Completed with Errors"
    else
      "Import Failed"
    end
  end

  def status_icon_path
    case result_type
    when :success
      "M5 13l4 4L19 7"
    when :partial
      "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
    else
      "M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
    end
  end

  def processing_rate
    return "N/A" if result.processing_time.nil? || result.processing_time == 0

    "#{result.domains_per_second} domains/second"
  end

  def has_imported_domains?
    result.imported_domains.any?
  end

  def has_failed_domains?
    result.failed_domains.any?
  end

  def mobile_friendly_errors
    result.failed_domains.map do |failed_domain|
      {
        summary: "Row #{failed_domain[:row]}: #{failed_domain[:domain].presence || '(blank)'}",
        errors: failed_domain[:errors].join(", ")
      }
    end
  end
end
