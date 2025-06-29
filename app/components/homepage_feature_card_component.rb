# frozen_string_literal: true

class HomepageFeatureCardComponent < ViewComponent::Base
  def initialize(title:, description:, icon:, color:, features:, link_path:, link_text:, available: true)
    @title = title
    @description = description
    @icon = icon
    @color = color
    @features = features
    @link_path = link_path
    @link_text = link_text
    @available = available
  end

  private

  attr_reader :title, :description, :icon, :color, :features, :link_path, :link_text, :available

  def icon_classes
    "w-8 h-8 #{color[:icon]}"
  end

  def icon_container_classes
    "w-16 h-16 #{color[:background]} rounded-xl flex items-center justify-center mb-6"
  end

  def button_classes
    if available
      "inline-flex items-center justify-center px-6 py-3 text-base font-medium text-white #{color[:button]} rounded-lg hover:shadow-lg transform hover:-translate-y-0.5 transition-all duration-200 focus:ring-4 focus:ring-opacity-50 #{color[:focus]}"
    else
      "inline-flex items-center justify-center px-6 py-3 text-base font-medium text-gray-500 bg-gray-100 rounded-lg cursor-not-allowed dark:text-gray-400 dark:bg-gray-700"
    end
  end

  def card_classes
    base = "p-8 bg-white border border-gray-200 rounded-2xl shadow-sm dark:bg-gray-800 dark:border-gray-700 transition-all duration-300"
    if available
      "#{base} hover:shadow-xl hover:-translate-y-1"
    else
      "#{base} relative overflow-hidden"
    end
  end
end
