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
    base_classes = "w-full table-auto text-sm text-left text-gray-500 dark:text-gray-400"
    [ base_classes, options[:class] ].compact.join(" ")
  end

  def wrapper_classes
    "relative overflow-x-auto shadow-md sm:rounded-lg w-full"
  end
end
