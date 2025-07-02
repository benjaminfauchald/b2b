# frozen_string_literal: true

class CompanyProfileExtractionButtonComponent < ViewComponent::Base
  def initialize(company:)
    @company = company
  end

  private

  attr_reader :company

  def can_extract_profiles?
    company.best_linkedin_url.present?
  end

  def profile_extraction_path
    queue_single_profile_extraction_people_path(company_id: company.id)
  end

  def button_text
    if has_recent_extraction?
      "Re-extract Profiles"
    else
      "Extract LinkedIn Profiles"
    end
  end

  def button_disabled?
    !can_extract_profiles?
  end

  def has_recent_extraction?
    recent_audit = company.service_audit_logs
      .where(service_name: "person_profile_extraction", status: "success")
      .where("completed_at > ?", 7.days.ago)
      .exists?
  end

  def has_extracted_profiles?
    company.service_audit_logs
      .where(service_name: "person_profile_extraction", status: "success")
      .exists? && company.people.any?
  end

  def profile_summary
    return nil unless has_extracted_profiles?

    people = company.people
    {
      total: people.count,
      emails: people.where.not(email: [ nil, "" ]).count,
      phones: people.where.not(phone: [ nil, "" ]).count
    }
  end

  def last_extraction_date
    latest_log = company.service_audit_logs
      .where(service_name: "person_profile_extraction", status: "success")
      .order(completed_at: :desc)
      .first

    latest_log&.completed_at
  end

  def disabled_reason
    if company.linkedin_url.blank? && company.linkedin_ai_url.blank?
      "No LinkedIn URL available"
    elsif company.linkedin_url.blank? && company.linkedin_ai_url.present? && company.linkedin_ai_confidence.present? && company.linkedin_ai_confidence < 80
      "LinkedIn AI confidence too low (#{company.linkedin_ai_confidence}%) - check the box above to use anyway"
    else
      "LinkedIn URL required"
    end
  end

  def button_classes
    base_classes = "w-full px-4 py-2 text-sm font-medium rounded-lg focus:ring-4 focus:outline-none transition-colors duration-200 flex items-center justify-center"

    if button_disabled?
      "#{base_classes} bg-gray-300 text-gray-500 cursor-not-allowed dark:bg-gray-700 dark:text-gray-400"
    else
      "#{base_classes} text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
    end
  end
end
