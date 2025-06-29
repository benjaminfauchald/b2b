class Person < ApplicationRecord
  include ServiceAuditable

  belongs_to :company, optional: true

  validates :name, presence: true
  validates :profile_url, uniqueness: { allow_blank: true }

  scope :needs_profile_extraction, -> {
    left_joins(:service_audit_logs)
      .where(
        service_audit_logs: { id: nil }
      )
      .or(
        joins(:service_audit_logs)
          .where(
            service_audit_logs: {
              service_name: "person_profile_extraction",
              status: [ "failed", "error" ]
            }
          )
          .where(
            "service_audit_logs.created_at < ?",
            24.hours.ago
          )
      )
      .distinct
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
end
