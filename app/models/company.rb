# frozen_string_literal: true

class Company < ApplicationRecord
  include ServiceAuditable

  # Associations
  has_many :service_audit_logs, as: :auditable, dependent: :nullify
  has_many :people, dependent: :destroy
  has_one :domain, dependent: :destroy
  has_many :linkedin_company_lookups, dependent: :destroy

  # Validations
  validates :registration_number, presence: true, uniqueness: true
  validates :linkedin_company_id, uniqueness: true, allow_nil: true, numericality: { only_integer: true }
  validates :linkedin_slug, uniqueness: true, allow_nil: true

  # Callbacks
  before_save :auto_populate_linkedin_url_from_ai

  # Country filtering scope
  scope :by_country, ->(country_code) { where(source_country: country_code) if country_code.present? }

  # Scopes for financial data
  scope :with_financial_data, -> { where.not(ordinary_result: nil, annual_result: nil) }
  scope :without_financial_data, -> { where(ordinary_result: nil, annual_result: nil) }

  # Base eligibility for financial data service (used for calculating totals/percentages)
  scope :financial_data_eligible, -> {
    where(
      source_country: "NO",
      source_registry: "brreg",
      organization_form_code: [ "AS", "ASA", "DA", "ANS" ]
    )
  }

  # Scope for companies that need financial data processing (eligible + no data yet)
  scope :financial_data_needing, -> {
    financial_data_eligible.where(ordinary_result: nil)
  }
  scope :needs_financial_update, -> {
    service_config = ServiceConfiguration.find_by(service_name: "company_financial_data")
    refresh_threshold = service_config&.refresh_interval_hours&.hours&.ago || 30.days.ago

    # Get IDs of companies with recent successful audits
    recent_success_ids = ServiceAuditLog
      .where(
        auditable_type: "Company",
        service_name: "company_financial_data",
        status: ServiceAuditLog.statuses[:success]
      )
      .where("completed_at > ?", refresh_threshold)
      .select(:auditable_id)
      .distinct
      .pluck(:auditable_id)

    # Start with companies that need financial data (eligible + no data yet)
    query = financial_data_needing

    # Only exclude if there are actually IDs to exclude
    if recent_success_ids.any?
      query = query.where.not(id: recent_success_ids)
    end

    query
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

  # Companies that have successfully completed web discovery
  scope :with_web_discovery, -> {
    where.not(web_pages: nil)
    .where("web_pages != '{}' AND jsonb_array_length(web_pages) > 0")
  }

  # Companies that have attempted web discovery but got no results
  scope :without_web_discovery, -> {
    where("web_pages IS NULL OR web_pages = '{}' OR jsonb_array_length(web_pages) = 0")
  }

  # Update web discovery scopes to order by revenue (highest first)
  scope :web_discovery_candidates_ordered, -> {
    web_discovery_candidates.order(operating_revenue: :desc)
  }

  scope :needing_web_discovery_ordered, -> {
    needing_web_discovery.order(operating_revenue: :desc)
  }

  # Scopes for LinkedIn discovery
  # Companies with revenue > 10M NOK that need LinkedIn discovery
  scope :linkedin_discovery_candidates, -> {
    where("operating_revenue > ?", 10_000_000)
    .order(operating_revenue: :desc)
  }

  # Companies that are LinkedIn discovery candidates AND have no LinkedIn data yet
  # AND haven't been processed recently (within the refresh interval)
  scope :needing_linkedin_discovery, -> {
    linkedin_discovery_candidates
    .where("(linkedin_url IS NULL OR linkedin_url = '') AND (linkedin_ai_url IS NULL OR linkedin_ai_url = '')")
    .where("NOT EXISTS (
      SELECT 1 FROM service_audit_logs 
      WHERE service_audit_logs.auditable_type = 'Company' 
      AND service_audit_logs.auditable_id = companies.id 
      AND service_audit_logs.service_name = 'company_linkedin_discovery'
      AND service_audit_logs.status = ?
      AND service_audit_logs.completed_at > ?
    )", ServiceAuditLog::STATUS_SUCCESS, 720.hours.ago)
  }

  # Companies that are LinkedIn discovery candidates regardless of processing status
  scope :linkedin_discovery_potential, -> {
    linkedin_discovery_candidates
  }

  # Scopes for Profile Extraction
  # Companies that are ready for LinkedIn profile extraction
  # Includes companies with either linkedin_url OR linkedin_ai_url with confidence >= 50%
  scope :profile_extraction_candidates, -> {
    where(
      "(linkedin_url IS NOT NULL AND linkedin_url != '') OR " \
      "(linkedin_ai_url IS NOT NULL AND linkedin_ai_url != '' AND linkedin_ai_confidence >= 80)"
    ).order(operating_revenue: :desc)
  }

  # Companies that need profile extraction (candidates that have no persons attached yet)
  scope :needing_profile_extraction, -> {
    profile_extraction_candidates
      .left_joins(:people)
      .where(people: { id: nil })
  }

  # Scopes for LinkedIn company association
  scope :with_linkedin_identifiers, -> {
    where.not(linkedin_company_id: nil)
      .or(where.not(linkedin_slug: nil))
  }
  
  scope :needs_linkedin_slug_population, -> {
    where(linkedin_slug: nil)
      .where(
        "(linkedin_url IS NOT NULL AND linkedin_url != '') OR " \
        "(linkedin_ai_url IS NOT NULL AND linkedin_ai_url != '')"
      )
  }

  # Total potential companies for profile extraction (for progress tracking)
  scope :profile_extraction_potential, -> {
    profile_extraction_candidates
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
      .where(service_name: "company_financial_data", status: :success)
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

  # Get the best LinkedIn URL for profile extraction
  # Prefers manual linkedin_url over AI-discovered linkedin_ai_url
  def best_linkedin_url
    if linkedin_url.present?
      linkedin_url
    elsif linkedin_ai_url.present? && linkedin_ai_confidence.present? && linkedin_ai_confidence >= 80
      linkedin_ai_url
    else
      nil
    end
  end

  # Check if company is ready for profile extraction
  def ready_for_profile_extraction?
    best_linkedin_url.present?
  end

  # Returns the status of the most recent financial data update via SCT
  def financial_data_status
    audit = ServiceAuditLog.where(auditable: self, service_name: "company_financial_data").order(completed_at: :desc).first
    return "pending" if audit.nil?
    audit.success? ? "success" : "failed"
  end

  # Returns the completed_at timestamp of the most recent financial data update via SCT
  def last_financial_update_at
    ServiceAuditLog.where(auditable: self, service_name: "company_financial_data", status: ServiceAuditLog.statuses[:success])
      .order(completed_at: :desc)
      .limit(1)
      .pick(:completed_at)
  end

  # For backward compatibility
  def last_financial_audit
    @last_financial_audit ||= ServiceAuditLog
      .where(auditable: self, service_name: "company_financial_data")
      .order(completed_at: :desc)
      .first
  end

  private

  # Auto-populate linkedin_url from AI when confidence is high enough
  def auto_populate_linkedin_url_from_ai
    # Only auto-populate if:
    # 1. linkedin_url is blank OR it was previously auto-populated from AI
    # 2. AI URL exists with high confidence (>= 80%)
    # 3. AI confidence has changed or AI URL has changed

    # Check if linkedin_url was auto-populated (matches old AI URL)
    was_auto_populated = linkedin_url.present? &&
                        linkedin_ai_url_was.present? &&
                        linkedin_url == linkedin_ai_url_was

    if (linkedin_url.blank? || was_auto_populated) &&
       linkedin_ai_url.present? &&
       linkedin_ai_confidence.present? &&
       linkedin_ai_confidence >= 80 &&
       (linkedin_ai_confidence_changed? || linkedin_ai_url_changed?)

      self.linkedin_url = linkedin_ai_url
      Rails.logger.info "Auto-populated linkedin_url from AI for company #{id}: #{linkedin_ai_url} (confidence: #{linkedin_ai_confidence}%)"
    end
  end
end
