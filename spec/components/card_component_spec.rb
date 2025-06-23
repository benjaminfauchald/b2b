# frozen_string_literal: true

require "rails_helper"

RSpec.describe CardComponent, type: :component do
  it "renders without title and description" do
    render_inline(described_class.new) { "Content" }

    expect(page).to have_css("div.bg-white")
    expect(page).to have_text("Content")
    expect(page).not_to have_css("h3")
    expect(page).not_to have_css("p.text-gray-600")
  end

  it "renders with title" do
    render_inline(described_class.new(title: "Test Card")) { "Content" }

    expect(page).to have_css("h3", text: "Test Card")
    expect(page).to have_text("Content")
  end

  it "renders with title and description" do
    render_inline(described_class.new(title: "Test Card", description: "Test description")) { "Content" }

    expect(page).to have_css("h3", text: "Test Card")
    expect(page).to have_css("p", text: "Test description")
    expect(page).to have_text("Content")
  end

  it "renders with footer slot" do
    render_inline(described_class.new(title: "Test Card")) do |component|
      component.with_footer { "Footer content" }
      "Main content"
    end

    expect(page).to have_text("Main content")
    expect(page).to have_css("div.border-t")
    expect(page).to have_text("Footer content")
  end

  it "applies correct styling classes" do
    render_inline(described_class.new) { "Content" }

    expect(page).to have_css("div.bg-white.dark\\:bg-gray-800")
    expect(page).to have_css("div.rounded-lg")
    expect(page).to have_css("div.shadow")
  end
end
