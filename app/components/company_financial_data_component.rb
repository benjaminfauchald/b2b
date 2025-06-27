# frozen_string_literal: true

class CompanyFinancialDataComponent < ViewComponent::Base
  include ActionView::Helpers::NumberHelper

  def initialize(company:)
    @company = company
  end

  private

  attr_reader :company

  def has_financial_data?
    company.revenue.present? || company.profit.present? || company.equity.present?
  end

  def financial_metrics
    [
      {
        label: "Revenue",
        value: company.revenue,
        format: :currency,
        color: revenue_color
      },
      {
        label: "Profit",
        value: company.profit,
        format: :currency,
        color: profit_color
      },
      {
        label: "Equity",
        value: company.equity,
        format: :currency,
        color: "text-gray-900"
      },
      {
        label: "Total Assets",
        value: company.total_assets,
        format: :currency,
        color: "text-gray-900"
      }
    ]
  end

  def asset_breakdown
    return [] unless company.current_assets.present? || company.fixed_assets.present?

    [
      { label: "Current Assets", value: company.current_assets, percentage: current_assets_percentage },
      { label: "Fixed Assets", value: company.fixed_assets, percentage: fixed_assets_percentage }
    ]
  end

  def liability_breakdown
    return [] unless company.current_liabilities.present? || company.long_term_liabilities.present?

    [
      { label: "Current Liabilities", value: company.current_liabilities, percentage: current_liabilities_percentage },
      { label: "Long-term Liabilities", value: company.long_term_liabilities, percentage: long_term_liabilities_percentage }
    ]
  end

  def format_value(value, format)
    return "—" unless value.present?

    case format
    when :currency
      number_to_currency(value, unit: "NOK ", precision: 0)
    when :percentage
      "#{value}%"
    else
      value.to_s
    end
  end

  def revenue_color
    "text-gray-900"
  end

  def profit_color
    return "text-gray-900" unless company.profit.present?
    company.profit >= 0 ? "text-green-600" : "text-red-600"
  end

  def current_assets_percentage
    return 0 unless company.total_assets.present? && company.total_assets > 0 && company.current_assets.present?
    ((company.current_assets.to_f / company.total_assets) * 100).round(1)
  end

  def fixed_assets_percentage
    return 0 unless company.total_assets.present? && company.total_assets > 0 && company.fixed_assets.present?
    ((company.fixed_assets.to_f / company.total_assets) * 100).round(1)
  end

  def current_liabilities_percentage
    total_liabilities = (company.current_liabilities || 0) + (company.long_term_liabilities || 0)
    return 0 unless total_liabilities > 0 && company.current_liabilities.present?
    ((company.current_liabilities.to_f / total_liabilities) * 100).round(1)
  end

  def long_term_liabilities_percentage
    total_liabilities = (company.current_liabilities || 0) + (company.long_term_liabilities || 0)
    return 0 unless total_liabilities > 0 && company.long_term_liabilities.present?
    ((company.long_term_liabilities.to_f / total_liabilities) * 100).round(1)
  end

  def financial_year
    company.year || "Unknown"
  end

  def last_updated
    return "Never" unless company.financial_data_updated_at
    "#{time_ago_in_words(company.financial_data_updated_at)} ago"
  end
end
