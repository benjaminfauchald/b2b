# frozen_string_literal: true

class HomepageStatsComponent < ViewComponent::Base
  def initialize(stats:)
    @stats = stats
  end

  private

  attr_reader :stats
end