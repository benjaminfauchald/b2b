# frozen_string_literal: true

class HomepageFeaturesGridComponent < ViewComponent::Base
  def initialize(features:)
    @features = features
  end

  private

  attr_reader :features

  def icon_colors
    [
      {
        background: "bg-gradient-to-br from-blue-500 to-blue-600",
        icon: "text-white"
      },
      {
        background: "bg-gradient-to-br from-green-500 to-green-600",
        icon: "text-white"
      },
      {
        background: "bg-gradient-to-br from-purple-500 to-purple-600",
        icon: "text-white"
      },
      {
        background: "bg-gradient-to-br from-orange-500 to-orange-600",
        icon: "text-white"
      }
    ]
  end
end
