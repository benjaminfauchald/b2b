# frozen_string_literal: true

class TableComponent < ViewComponent::Base
  def initialize(headers:, rows:, **options)
    @headers = headers
    @rows = rows
    @options = options
  end

  private

  attr_reader :headers, :rows, :options

  def table_classes
    base_classes = "min-w-full table-auto text-sm text-left text-gray-500 dark:text-gray-400"
    [ base_classes, options[:class] ].compact.join(" ")
  end

  def wrapper_classes
    "relative overflow-x-auto shadow-md sm:rounded-lg w-full bg-white dark:bg-gray-800"
  end

  def header_classes
    "bg-gray-50 dark:bg-gray-700"
  end

  def header_cell_classes
    "px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider"
  end

  def body_classes
    "bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700"
  end

  def row_classes(index)
    base_classes = "hover:bg-gray-50 dark:hover:bg-gray-700"
    # Note: CSS :nth-child() is 1-indexed, so index 1 (second row) should have bg-gray-50
    alternate_class = (index + 1).even? ? "bg-gray-50 dark:bg-gray-800" : "bg-white dark:bg-gray-800"
    "#{base_classes} #{alternate_class}"
  end

  def cell_classes
    "px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white"
  end

  def first_cell_classes
    "px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-white"
  end
end
