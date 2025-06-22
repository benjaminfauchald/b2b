# frozen_string_literal: true

class ButtonComponent < ViewComponent::Base
  def initialize(text:, variant: :primary, size: :medium, **options)
    @text = text
    @variant = variant
    @size = size
    @options = options
  end

  private

  attr_reader :text, :variant, :size, :options

  def css_classes
    base_classes = "inline-flex items-center justify-center font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 transition-colors duration-200"
    
    variant_classes = {
      primary: "bg-blue-600 hover:bg-blue-700 text-white focus:ring-blue-500",
      secondary: "bg-gray-200 hover:bg-gray-300 text-gray-900 focus:ring-gray-500",
      danger: "bg-red-600 hover:bg-red-700 text-white focus:ring-red-500"
    }
    
    size_classes = {
      small: "px-3 py-2 text-sm",
      medium: "px-4 py-2 text-base",
      large: "px-6 py-3 text-lg"
    }
    
    [
      base_classes,
      variant_classes[variant],
      size_classes[size],
      options[:class]
    ].compact.join(" ")
  end
end
