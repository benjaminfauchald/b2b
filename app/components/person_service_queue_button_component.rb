# frozen_string_literal: true

class PersonServiceQueueButtonComponent < ViewComponent::Base
  include ActionView::Helpers::NumberHelper

  def initialize(service_name:, title:, icon:, action_path:, queue_name:)
    @service_name = service_name
    @title = title
    @icon = icon
    @action_path = action_path
    @queue_name = queue_name
  end

  private

  attr_reader :service_name, :title, :icon, :action_path, :queue_name

  def items_needing_service
    case service_name
    when "person_profile_extraction"
      Company.needing_service("person_profile_extraction").count
    when "person_email_extraction"
      Person.needing_email_extraction.count
    when "person_social_media_extraction"
      Person.needing_social_media_extraction.count
    else
      0
    end
  end

  # For profile extraction, show total potential companies that could be processed
  def profile_extraction_potential
    return 0 unless service_name == "person_profile_extraction"
    Company.profile_extraction_potential.count
  end

  # Calculate items that have been successfully processed for this service
  def items_completed
    case service_name
    when "person_profile_extraction"
      # Count companies that have actually been successfully processed by profile extraction service
      # Include both service names: "person_profile_extraction" and "phantom_buster_profile_extraction"
      ServiceAuditLog
        .joins("JOIN companies ON companies.id = CAST(service_audit_logs.auditable_id AS INTEGER)")
        .where(service_name: ["person_profile_extraction", "phantom_buster_profile_extraction"], status: "success")
        .where(auditable_type: "Company")
        .where(
          "(companies.linkedin_url IS NOT NULL AND companies.linkedin_url != '') OR " \
          "(companies.linkedin_ai_url IS NOT NULL AND companies.linkedin_ai_url != '' AND companies.linkedin_ai_confidence >= 80)"
        )
        .count
    when "person_email_extraction"
      Person.where.not(email: nil).where.not(email: "").count
    when "person_social_media_extraction"
      Person.where.not(social_media_data: nil).count
    else
      0
    end
  end

  # Calculate completion percentage
  def completion_percentage
    total = case service_name
    when "person_profile_extraction"
      profile_extraction_potential
    else
      return 0
    end

    return 0 if total == 0

    completed = items_completed
    percentage = (completed.to_f / total.to_f) * 100

    # Round to 1 decimal place for small percentages, 0 decimals for large ones
    if percentage < 1
      percentage.round(1)
    else
      percentage.round
    end
  end

  # Check if this is the profile extraction service
  def profile_extraction_service?
    service_name == "person_profile_extraction"
  end

  # Check if this service should show completion percentage
  def show_completion_percentage?
    profile_extraction_service?
  end

  def queue_depth
    # For now, return 0 as these are mock services
    0
  end

  def button_classes
    # Flowbite primary button classes
    "text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
  end

  def card_classes
    # Flowbite card classes
    "p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
  end

  def input_classes
    # Flowbite form input classes
    "bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
  end

  def label_classes
    # Flowbite label classes
    "block mb-2 text-sm font-medium text-gray-900 dark:text-white"
  end

  def text_muted_classes
    # Muted text classes
    "text-sm text-gray-600 dark:text-gray-400"
  end

  def heading_classes
    # Heading classes
    "mb-2 text-lg font-semibold text-gray-900 dark:text-white"
  end
end
