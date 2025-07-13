class Person < ApplicationRecord
  include ServiceAuditable

  belongs_to :company, optional: true
  has_many :email_verification_attempts, dependent: :destroy

  validates :name, presence: true
  validates :email, uniqueness: { allow_blank: true }
  validates :profile_url, uniqueness: { allow_blank: true }

  scope :needs_profile_extraction, -> {
    # Get people with no profile extraction logs
    without_logs = left_joins(:service_audit_logs)
      .where(service_audit_logs: { id: nil })

    # Get people with failed/error logs older than 24 hours
    with_old_failures = joins(:service_audit_logs)
      .where(
        service_audit_logs: {
          service_name: "person_profile_extraction",
          status: [ "failed", "error" ]
        }
      )
      .where("service_audit_logs.created_at < ?", 24.hours.ago)

    # Combine using where(id: ...) to avoid incompatible OR
    where(id: without_logs).or(where(id: with_old_failures)).distinct
  }

  scope :needs_email_extraction, -> {
    where(email_extracted_at: nil)
      .or(where("email_extracted_at < ?", 7.days.ago))
      .where.not(name: nil)
  }

  scope :needs_social_media_extraction, -> {
    where(social_media_extracted_at: nil)
      .or(where("social_media_extracted_at < ?", 30.days.ago))
      .where.not(name: nil)
  }

  scope :with_profile_data, -> { where.not(profile_data: nil) }
  scope :with_email_data, -> { where.not(email_data: nil) }
  scope :with_social_media_data, -> { where.not(social_media_data: nil) }

  scope :recent_extractions, -> { where("profile_extracted_at > ?", 7.days.ago) }
  scope :imported_with_tag, ->(tag) { where(import_tag: tag) }

  # ZeroBounce data scopes
  scope :with_zerobounce_data, -> { where.not(zerobounce_status: nil) }
  scope :without_zerobounce_data, -> { where(zerobounce_status: nil) }
  scope :zerobounce_valid, -> { where(zerobounce_status: "valid") }
  scope :zerobounce_invalid, -> { where(zerobounce_status: "invalid") }
  scope :verification_systems_agree, -> {
    with_zerobounce_data.where.not(email_verification_status: nil).select { |p| p.verification_systems_agree? }
  }
  scope :verification_systems_disagree, -> {
    with_zerobounce_data.where.not(email_verification_status: nil).reject { |p| p.verification_systems_agree? }
  }

  # Service extraction scopes for consistency with button component
  scope :needing_profile_extraction, -> { where(profile_data: nil) }
  scope :needing_email_extraction, -> { where(email: [ nil, "" ]) }
  scope :needing_social_media_extraction, -> { where(social_media_data: nil) }

  # Potential scopes for completion percentage calculations
  scope :profile_extraction_potential, -> { all }
  scope :email_extraction_potential, -> { all }
  scope :social_media_extraction_potential, -> { all }

  def full_profile_data
    {
      name: name,
      title: title,
      company_name: company_name,
      location: location,
      profile_url: profile_url,
      email: email,
      phone: phone,
      connection_degree: connection_degree,
      profile_data: profile_data,
      email_data: email_data,
      social_media_data: social_media_data
    }
  end

  def needs_profile_extraction?
    profile_extracted_at.nil? || profile_extracted_at < 30.days.ago
  end

  def needs_email_extraction?
    email_extracted_at.nil? || email_extracted_at < 7.days.ago
  end

  def needs_social_media_extraction?
    social_media_extracted_at.nil? || social_media_extracted_at < 30.days.ago
  end

  # Email verification methods
  def email_verified?
    email_verification_status == "valid"
  end

  def email_unverified?
    email_verification_status == "unverified"
  end

  def needs_email_verification?
    email.present? && (email_unverified? || email_verification_checked_at.nil? || email_verification_checked_at < 30.days.ago)
  end

  # ZeroBounce comparison methods
  def has_zerobounce_data?
    zerobounce_status.present?
  end

  def zerobounce_verified?
    zerobounce_status == "valid"
  end

  def zerobounce_invalid?
    zerobounce_status == "invalid"
  end

  def verification_systems_agree?
    return false unless has_zerobounce_data? && email_verification_status.present?

    # Map our statuses to ZeroBounce equivalents for comparison
    our_status_mapped = case email_verification_status
    when "valid" then "valid"
    when "invalid" then "invalid"
    when "suspect" then "catch-all"
    when "catch_all" then "catch-all"  # New enhanced status
    else "unknown"
    end

    zerobounce_status == our_status_mapped
  end

  def confidence_score_comparison
    return nil unless has_zerobounce_data? && email_verification_confidence.present?

    # Convert ZeroBounce 0-10 scale to our 0.0-1.0 scale
    zb_confidence_normalized = zerobounce_quality_score&./ 10.0
    our_confidence = email_verification_confidence

    {
      our_confidence: our_confidence,
      zerobounce_confidence: zb_confidence_normalized,
      difference: (our_confidence - zb_confidence_normalized).abs,
      systems_agree: verification_systems_agree?
    }
  end

  def full_name
    name
  end

  # Normalize LinkedIn URL for consistent storage and comparison
  def self.normalize_linkedin_url(url)
    return nil if url.blank?

    url = url.to_s.strip
    
    # Only process if it contains linkedin.com
    return nil unless url.include?("linkedin.com")
    
    # Remove anything after comma (for CSV parsing issues)
    url = url.gsub(/,.*$/, "").strip
    
    # Normalize LinkedIn URLs
    # 1. Ensure https protocol
    url = "https://#{url}" unless url.start_with?("http")
    url = url.gsub(/^http:/, "https:")
    
    # 2. Parse and rebuild URL to normalize
    begin
      uri = URI.parse(url)
      
      # Ensure www subdomain for consistency
      uri.host = "www.linkedin.com" if uri.host == "linkedin.com"
      
      # Remove trailing slashes from path
      uri.path = uri.path.chomp("/") if uri.path
      
      # Remove query parameters (like ?param=value)
      uri.query = nil
      
      # Remove fragment (like #section)
      uri.fragment = nil
      
      # Return normalized URL
      uri.to_s
    rescue URI::InvalidURIError
      # If URL parsing fails, do basic cleaning
      url.gsub(/\?.*$/, "")  # Remove query params
         .gsub(/#.*$/, "")   # Remove fragments
         .chomp("/")         # Remove trailing slash
    end
  end

  # Normalize profile_url before saving
  before_validation :normalize_profile_url

  private

  def normalize_profile_url
    self.profile_url = self.class.normalize_linkedin_url(profile_url) if profile_url_changed?
  end
end
