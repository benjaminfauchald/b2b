# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageHeaderComponent, type: :component do
  it "renders with required title" do
    render_inline(described_class.new(title: "Test Page"))

    expect(page).to have_css("h1", text: "Test Page")
    expect(page).not_to have_css("p.text-gray-600")
  end

  it "renders with title and subtitle" do
    render_inline(described_class.new(title: "Test Page", subtitle: "Page description"))

    expect(page).to have_css("h1", text: "Test Page")
    expect(page).to have_css("p", text: "Page description")
  end

  it "renders with actions slot" do
    render_inline(described_class.new(title: "Test Page")) do |component|
      component.with_actions { "<button>Action</button>".html_safe }
    end

    expect(page).to have_css("h1", text: "Test Page")
    expect(page).to have_css("button", text: "Action")
  end

  it "applies correct styling classes" do
    render_inline(described_class.new(title: "Test Page"))

    expect(page).to have_css("div.bg-white.dark\\:bg-gray-800")
    expect(page).to have_css("div.shadow")
    expect(page).to have_css("h1.text-2xl")
  end
end
