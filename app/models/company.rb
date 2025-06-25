# frozen_string_literal: true

class Company < ApplicationRecord
  include ServiceAuditable

  # Associations
  has_many :service_audit_logs, as: :auditable, dependent: :nullify

  # Validations
  validates :registration_number, presence: true, uniqueness: true

  # Scopes for financial data
  scope :with_financial_data, -> { where.not(ordinary_result: nil, annual_result: nil) }
  scope :without_financial_data, -> { where(ordinary_result: nil, annual_result: nil) }
  scope :needs_financial_update, -> {
    service_config = ServiceConfiguration.find_by(service_name: "company_financial_data")
    refresh_threshold = service_config&.refresh_interval_hours&.hours&.ago || 30.days.ago
    subquery = ServiceAuditLog
      .where(service_name: "company_financial_data", status: ServiceAuditLog.statuses[:success])
      .where("completed_at > ?", refresh_threshold)
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

  # Scopes for web discovery
  # Companies with revenue > 10M NOK and no website that need web discovery
  scope :web_discovery_candidates, -> {
    where("operating_revenue > ?", 10_000_000)
    .where("website IS NULL OR website = ''")
  }

  # Companies that are web discovery candidates AND haven't been processed yet
  scope :needing_web_discovery, -> {
    web_discovery_candidates
    .where("web_pages IS NULL OR web_pages = '{}' OR jsonb_array_length(web_pages) = 0")
  }

  # Companies that are web discovery candidates regardless of processing status
  # Used for showing total potential in UI
  scope :web_discovery_potential, -> {
    web_discovery_candidates
  }

  # Update web discovery scopes to order by revenue (highest first)
  scope :web_discovery_candidates_ordered, -> {
    web_discovery_candidates.order(operating_revenue: :desc)
  }

  scope :needing_web_discovery_ordered, -> {
    needing_web_discovery.order(operating_revenue: :desc)
  }

  # Scopes for LinkedIn discovery
  # Companies with revenue > 10M NOK and no LinkedIn URL that need LinkedIn discovery
  scope :linkedin_discovery_candidates, -> {
    where("operating_revenue > ?", 10_000_000)
    .where("linkedin_url IS NULL OR linkedin_url = ''")
    .order(operating_revenue: :desc)
  }

  # Companies that are LinkedIn discovery candidates AND haven't been processed yet
  scope :needing_linkedin_discovery, -> {
    linkedin_discovery_candidates
    .where("linkedin_data IS NULL OR linkedin_data = '{}' OR jsonb_array_length(linkedin_data) = 0")
    .order(operating_revenue: :desc)
  }

  # Companies that are LinkedIn discovery candidates regardless of processing status
  scope :linkedin_discovery_potential, -> {
    linkedin_discovery_candidates
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
