# frozen_string_literal: true

class PageHeaderComponentPreview < ViewComponent::Preview
  def default
    render(PageHeaderComponent.new(title: "Dashboard", subtitle: "Welcome to your analytics dashboard"))
  end

  def with_actions
    render(PageHeaderComponent.new(title: "Users", subtitle: "Manage your application users")) do |component|
      component.with_actions do
        "<button class='px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700'>Add User</button>".html_safe
      end
    end
  end

  def minimal
    render(PageHeaderComponent.new(title: "Settings"))
  end
end
