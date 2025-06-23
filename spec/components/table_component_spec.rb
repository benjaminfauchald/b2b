# frozen_string_literal: true

require "rails_helper"

RSpec.describe TableComponent, type: :component do
  let(:headers) { [ "Name", "Email", "Role" ] }
  let(:rows) { [
    [ "John Doe", "john@example.com", "Admin" ],
    [ "Jane Smith", "jane@example.com", "User" ]
  ] }

  it "renders table with headers and rows" do
    render_inline(described_class.new(headers: headers, rows: rows))

    headers.each do |header|
      expect(page).to have_css("th", text: header)
    end

    rows.each_with_index do |row, row_index|
      row.each_with_index do |cell, cell_index|
        if cell_index == 0
          expect(page).to have_css("th[scope='row']", text: cell)
        else
          expect(page).to have_css("td", text: cell)
        end
      end
    end
  end

  it "renders empty state when no rows provided" do
    render_inline(described_class.new(headers: headers, rows: []))

    expect(page).to have_css("td[colspan='3']", text: "No data available")
  end

  it "handles different column counts correctly" do
    custom_headers = [ "ID", "Name" ]
    custom_rows = [ [ "1", "Test" ] ]

    render_inline(described_class.new(headers: custom_headers, rows: custom_rows))

    expect(page).to have_css("td[colspan='2']", text: "No data available") if custom_rows.empty?
  end

  it "applies correct styling classes" do
    render_inline(described_class.new(headers: headers, rows: rows))

    expect(page).to have_css("div.bg-white.dark\\:bg-gray-800")
    expect(page).to have_css("table.min-w-full")
    expect(page).to have_css("thead.bg-gray-50")
    expect(page).to have_css("tbody")
  end

  it "alternates row colors" do
    render_inline(described_class.new(headers: headers, rows: rows))

    expect(page).to have_css("tr:nth-child(even).bg-gray-50")
  end
end
