# frozen_string_literal: true

class CardComponent < ViewComponent::Base
  renders_one :footer

  def initialize(title: nil, description: nil, **options)
    @title = title
    @description = description
    @options = options
  end

  private

  attr_reader :title, :description, :options

  def css_classes
    base_classes = "p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
    [ base_classes, options[:class] ].compact.join(" ")
  end
end
