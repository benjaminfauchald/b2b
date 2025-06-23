# frozen_string_literal: true

class StatsCardComponent < ViewComponent::Base
  def initialize(label:, value:, icon: nil, trend: nil, trend_direction: nil, color: :blue, data_stat: nil)
    @label = label
    @value = value
    @icon = icon
    @trend = trend
    @trend_direction = trend_direction
    @color = color
    @data_stat = data_stat
  end

  private

  attr_reader :label, :value, :icon, :trend, :trend_direction, :color, :data_stat

  def color_classes
    colors = {
      blue: "text-blue-600 bg-blue-100 dark:bg-blue-900 dark:text-blue-300",
      green: "text-green-600 bg-green-100 dark:bg-green-900 dark:text-green-300",
      red: "text-red-600 bg-red-100 dark:bg-red-900 dark:text-red-300",
      yellow: "text-yellow-600 bg-yellow-100 dark:bg-yellow-900 dark:text-yellow-300",
      purple: "text-purple-600 bg-purple-100 dark:bg-purple-900 dark:text-purple-300"
    }
    colors[color] || colors[:blue]
  end

  def trend_icon
    return unless trend

    if trend_direction == "up"
      "↑"
    else
      "↓"
    end
  end

  def trend_color
    return unless trend
    trend_direction == "up" ? "text-green-600" : "text-red-600"
  end
end
