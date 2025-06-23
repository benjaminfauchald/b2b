# frozen_string_literal: true

class PageHeaderComponent < ViewComponent::Base
  renders_one :actions

  def initialize(title:, subtitle: nil)
    @title = title
    @subtitle = subtitle
  end

  private

  attr_reader :title, :subtitle
end
