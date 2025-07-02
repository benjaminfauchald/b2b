class Person < ApplicationRecord
  include ServiceAuditable

  belongs_to :company, optional: true
  has_many :email_verification_attempts, dependent: :destroy

  validates :name, presence: true
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

  # Service extraction scopes for consistency with button component
  scope :needing_profile_extraction, -> { needs_profile_extraction }
  scope :needing_email_extraction, -> { needs_email_extraction }
  scope :needing_social_media_extraction, -> { needs_social_media_extraction }

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

  def full_name
    name
  end
end
