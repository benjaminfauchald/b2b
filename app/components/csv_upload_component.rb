# frozen_string_literal: true

class CsvUploadComponent < ViewComponent::Base
  def initialize(max_size: "50MB", help_text: nil, **options)
    @max_size = max_size
    @help_text = help_text
    @options = options
  end

  private

  attr_reader :max_size, :help_text, :options

  def wrapper_classes
    base_classes = "w-full"
    [ base_classes, options[:class] ].compact.join(" ")
  end

  def upload_zone_classes
    [
      "flex flex-col items-center justify-center w-full h-64",
      "border-2 border-gray-300 border-dashed rounded-lg cursor-pointer",
      "bg-gray-50 dark:bg-gray-700",
      "hover:bg-gray-100 dark:border-gray-600 dark:hover:border-gray-500",
      "dark:hover:bg-gray-600 transition-colors duration-200"
    ].join(" ")
  end

  def icon_classes
    "w-8 h-8 mb-4 text-gray-500 dark:text-gray-400"
  end

  def primary_text_classes
    "mb-2 text-sm text-gray-500 dark:text-gray-400"
  end

  def secondary_text_classes
    "text-xs text-gray-500 dark:text-gray-400"
  end

  def file_input_classes
    "hidden"
  end

  def help_text_content
    help_text || "Format: domain,dns,www,mx"
  end

  def max_size_display
    "Maximum file size: #{max_size}"
  end
end
