# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatsCardComponent, type: :component do
  it "renders with required label and value" do
    render_inline(described_class.new(label: "Total Users", value: "1,234"))

    expect(page).to have_css("p", text: "Total Users")
    expect(page).to have_css("p", text: "1,234")
    expect(page).not_to have_css("span.text-4xl") # no icon
  end

  it "renders with icon" do
    render_inline(described_class.new(label: "Revenue", value: "$10,000", icon: "💰"))

    expect(page).to have_css("span", text: "💰")
    expect(page).to have_css("p", text: "Revenue")
    expect(page).to have_css("p", text: "$10,000")
  end

  it "renders with positive trend" do
    render_inline(described_class.new(
      label: "Sales",
      value: "500",
      trend: "+15%",
      trend_direction: "up"
    ))

    expect(page).to have_css("span.text-green-600", text: "↑ +15%")
  end

  it "renders with negative trend" do
    render_inline(described_class.new(
      label: "Errors",
      value: "12",
      trend: "-5%",
      trend_direction: "down"
    ))

    expect(page).to have_css("span.text-red-600", text: "↓ -5%")
  end

  it "applies correct styling classes" do
    render_inline(described_class.new(label: "Test", value: "100"))

    expect(page).to have_css("div.bg-white.dark\\:bg-gray-800")
    expect(page).to have_css("div.rounded-lg")
    expect(page).to have_css("div.shadow")
  end
end
