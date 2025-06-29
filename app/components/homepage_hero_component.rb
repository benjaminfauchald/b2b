# frozen_string_literal: true

class HomepageHeroComponent < ViewComponent::Base
  def initialize(title:, subtitle:, description:, version: nil)
    @title = title
    @subtitle = subtitle
    @description = description
    @version = version
  end

  private

  attr_reader :title, :subtitle, :description, :version
end