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

  def disabled_reason
    if company.linkedin_url.blank? && company.linkedin_ai_url.blank?
      "No LinkedIn URL available"
    elsif company.linkedin_ai_confidence.present? && company.linkedin_ai_confidence < 50
      "LinkedIn confidence too low (#{company.linkedin_ai_confidence}%)"
    else
      "LinkedIn URL required"
    end
  end

  def button_classes
    if button_disabled?
      "inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-400 bg-gray-100 cursor-not-allowed dark:bg-gray-700 dark:border-gray-600 dark:text-gray-500"
    else
      "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
    end
  end
end