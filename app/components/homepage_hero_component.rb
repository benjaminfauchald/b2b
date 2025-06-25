# frozen_string_literal: true

class HomepageHeroComponent < ViewComponent::Base
  def initialize(title:, subtitle:, description:)
    @title = title
    @subtitle = subtitle
    @description = description
  end

  private

  attr_reader :title, :subtitle, :description
end