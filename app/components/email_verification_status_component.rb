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

  # ZeroBounce comparison methods
  def has_zerobounce_data?
    person.has_zerobounce_data?
  end

  def zerobounce_status
    person.zerobounce_status
  end

  def zerobounce_quality_score
    person.zerobounce_quality_score
  end

  def zerobounce_confidence_normalized
    return nil unless zerobounce_quality_score
    zerobounce_quality_score / 10.0
  end

  def zerobounce_confidence_percentage
    return nil unless zerobounce_confidence_normalized
    (zerobounce_confidence_normalized * 100).round
  end

  def systems_agree?
    person.verification_systems_agree?
  end

  def confidence_comparison
    person.confidence_score_comparison
  end

  def zerobounce_status_text
    case zerobounce_status&.downcase
    when "valid"
      "Valid"
    when "invalid"
      "Invalid"
    when "catch-all"
      "Catch-All"
    when "unknown"
      "Unknown"
    when "do_not_mail"
      "Do Not Mail"
    when "spamtrap"
      "Spam Trap"
    when "abuse"
      "Abuse"
    when "disposable"
      "Disposable"
    else
      zerobounce_status&.humanize || "N/A"
    end
  end

  def zerobounce_status_color_classes
    case zerobounce_status&.downcase
    when "valid"
      "bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400"
    when "invalid", "do_not_mail", "spamtrap", "abuse", "disposable"
      "bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400"
    when "catch-all", "unknown"
      "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
    else
      "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
    end
  end

  def agreement_icon_classes
    if systems_agree?
      "text-green-600 dark:text-green-400"
    else
      "text-red-600 dark:text-red-400"
    end
  end

  def zerobounce_imported_at
    person.zerobounce_imported_at
  end

  def zerobounce_imported_text
    return nil unless zerobounce_imported_at
    
    days_ago = ((Time.current - zerobounce_imported_at) / 1.day).round
    
    if days_ago == 0
      "Imported today"
    elsif days_ago == 1
      "Imported yesterday"
    else
      "Imported #{days_ago} days ago"
    end
  end
end
