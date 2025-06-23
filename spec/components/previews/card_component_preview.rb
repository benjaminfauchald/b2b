# frozen_string_literal: true

class CardComponentPreview < ViewComponent::Preview
  def default
    render(CardComponent.new(title: "Example Card", description: "This is a sample card component")) do
      "Card content goes here"
    end
  end

  def with_footer
    render(CardComponent.new(title: "Card with Footer")) do |component|
      component.with_footer do
        "<a href='#' class='text-blue-600 hover:text-blue-800'>View Details</a>".html_safe
      end
      "Main content of the card"
    end
  end

  def minimal
    render(CardComponent.new) do
      "Simple card with just content"
    end
  end
end
