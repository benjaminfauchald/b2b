# frozen_string_literal: true

class StatsCardComponentPreview < ViewComponent::Preview
  def default
    render(StatsCardComponent.new(
      label: "Total Revenue",
      value: "$45,231.89",
      icon: "💰"
    ))
  end

  def with_positive_trend
    render(StatsCardComponent.new(
      label: "Active Users",
      value: "2,543",
      icon: "👥",
      trend: "+12.5%",
      trend_direction: "up"
    ))
  end

  def with_negative_trend
    render(StatsCardComponent.new(
      label: "Error Rate",
      value: "2.4%",
      icon: "⚠️",
      trend: "-8.2%",
      trend_direction: "down"
    ))
  end

  def minimal
    render(StatsCardComponent.new(
      label: "Total Orders",
      value: "1,234"
    ))
  end
end
