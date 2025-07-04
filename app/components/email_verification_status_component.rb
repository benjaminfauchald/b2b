# frozen_string_literal: true

class EmailVerificationStatusComponent < ViewComponent::Base
  attr_reader :person

  def initialize(person:)
    @person = person
  end

  def render?
    person.email.present?
  end

  private

  def status
    person.email_verification_status || "unverified"
  end

  def confidence
    person.email_verification_confidence || 0.0
  end

  def checked_at
    person.email_verification_checked_at
  end

  def status_text
    case status
    when "valid"
      "Valid"
    when "invalid"
      "Invalid"
    when "unverified"
      "Not Verified"
    when "greylist_retry"
      "Pending Retry"
    when "rate_limited"
      "Rate Limited"
    when "timeout"
      "Timeout"
    else
      "Unknown"
    end
  end

  def status_color_classes
    case status
    when "valid"
      "bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400"
    when "invalid"
      "bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400"
    when "unverified"
      "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
    when "greylist_retry", "rate_limited"
      "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
    when "timeout"
      "bg-orange-100 text-orange-800 dark:bg-orange-900/20 dark:text-orange-400"
    else
      "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
    end
  end

  def confidence_percentage
    (confidence * 100).round
  end

  def confidence_color
    if confidence >= 0.8
      "text-green-600 dark:text-green-400"
    elsif confidence >= 0.5
      "text-yellow-600 dark:text-yellow-400"
    else
      "text-red-600 dark:text-red-400"
    end
  end

  def last_checked_text
    return "Never checked" unless checked_at

    # If confidence is 0.0 and metadata is empty, this was likely imported, not verified
    if confidence == 0.0 && verification_metadata.blank?
      return "Imported (not verified)"
    end

    days_ago = ((Time.current - checked_at) / 1.day).round

    if days_ago == 0
      "Checked today"
    elsif days_ago == 1
      "Checked yesterday"
    else
      "Checked #{days_ago} days ago"
    end
  end

  def needs_verification?
    person.needs_email_verification?
  end

  def verification_metadata
    person.email_verification_metadata || {}
  end

  def show_details?
    status != "unverified" && verification_metadata.present?
  end
end
