# frozen_string_literal: true

class Company < ApplicationRecord
  # Associations
  has_many :service_audit_logs, as: :auditable, dependent: :nullify

  # Validations
  validates :registration_number, presence: true, uniqueness: true

  # Scopes for financial data
  scope :with_financial_data, -> { where.not(ordinary_result: nil, annual_result: nil) }
  scope :without_financial_data, -> { where(ordinary_result: nil, annual_result: nil) }
  scope :needs_financial_update, -> {
    twelve_months_ago = 12.months.ago
    subquery = ServiceAuditLog
      .where(service_name: "company_financials", status: ServiceAuditLog.statuses[:success])
      .where("completed_at > ?", twelve_months_ago)
      .select(:auditable_id)
      .distinct

    where(
      source_country: "NO",
      source_registry: "brreg",
      ordinary_result: nil,
      organization_form_code: [ "AS", "ASA", "DA", "ANS" ]
    ).where(
      "companies.id NOT IN (?)",
      subquery
    )
  }

  # Instance Methods

  # Update financial data asynchronously
  def update_financials_async
    CompanyFinancialsService.new(company_id: id).call
  end

  # Update financial data synchronously
  def update_financials_sync
    CompanyFinancialsService.new(company_id: id).call
  end

  # Check if financial data is missing
  def financial_data_missing?
    ordinary_result.nil? || annual_result.nil? || http_error.present? ||
      last_financial_audit.nil? || last_financial_audit.completed_at < 1.month.ago
  end

  # Check if financial data is stale
  def financial_data_stale?
    last_successful_audit = service_audit_logs
      .where(service_name: "company_financials", status: :success)
      .order(completed_at: :desc)
      .first

    last_successful_audit.nil? || last_successful_audit.completed_at < 12.months.ago
  end

  # Check if company needs a financial update
  def needs_financial_update?
    ordinary_result.nil? ||
    annual_result.nil? ||
    financial_data_stale?
  end

  # Get financial data summary
  def financial_data
    {
      ordinary_result: ordinary_result,
      annual_result: annual_result,
      operating_revenue: operating_revenue,
      operating_costs: operating_costs,
      last_updated: last_financial_audit&.completed_at || updated_at,
      status: financial_data_status
    }
  end

  # Returns the status of the most recent financial data update via SCT
  def financial_data_status
    audit = ServiceAuditLog.where(auditable: self, service_name: "company_financials").order(completed_at: :desc).first
    return "pending" if audit.nil?
    audit.success? ? "success" : "failed"
  end

  # Returns the completed_at timestamp of the most recent financial data update via SCT
  def last_financial_update_at
    ServiceAuditLog.where(auditable: self, service_name: "company_financials", status: ServiceAuditLog.statuses[:success])
      .order(completed_at: :desc)
      .limit(1)
      .pick(:completed_at)
  end

  # For backward compatibility
  def last_financial_audit
    @last_financial_audit ||= ServiceAuditLog
      .where(auditable: self, service_name: "company_financials")
      .order(completed_at: :desc)
      .first
  end
end
