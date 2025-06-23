# frozen_string_literal: true

class ButtonComponentPreview < ViewComponent::Preview
  def default
    render(ButtonComponent.new(text: "Click me"))
  end

  def primary
    render(ButtonComponent.new(text: "Primary Button", variant: :primary))
  end

  def secondary
    render(ButtonComponent.new(text: "Secondary Button", variant: :secondary))
  end

  def danger
    render(ButtonComponent.new(text: "Delete", variant: :danger))
  end

  def sizes
    content_tag :div, class: "space-y-4" do
      [
        render(ButtonComponent.new(text: "Small", size: :small)),
        render(ButtonComponent.new(text: "Medium", size: :medium)),
        render(ButtonComponent.new(text: "Large", size: :large))
      ].join.html_safe
    end
  end
end
