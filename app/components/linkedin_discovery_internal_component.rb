# frozen_string_literal: true

# ============================================================================
# LinkedIn Discovery Internal Component
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/linkedin_discovery_internal.rb
# 
# IMPORTANT: When making changes to this component:
# 1. Check IDM status: FeatureMemories::LinkedinDiscoveryInternal.plan_status
# 2. Update implementation_log with your changes
# 3. Follow the IDM communication protocol in CLAUDE.md
# ============================================================================
#
# ViewComponent for LinkedIn Discovery Internal feature
# Displays form for Sales Navigator URL input and service status
class LinkedinDiscoveryInternalComponent < ViewComponent::Base
  include Turbo::FramesHelper
  
  attr_reader :company, :service_config

  def initialize(company:)
    @company = company
    @service_config = ServiceConfiguration.find_by(service_name: "linkedin_discovery_internal")
  end

  def render?
    # Only show if service is configured and active
    service_config.present? && service_config.active?
  end

  private

  def service_active?
    service_config&.active?
  end

  def processing_status
    if company.linkedin_internal_processed
      "completed"
    elsif company.linkedin_internal_error_message.present?
      "error"
    elsif job_in_queue?
      "processing"
    else
      "pending"
    end
  end

  def status_badge_class
    case processing_status
    when "completed"
      "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"
    when "error"
      "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300"
    when "processing"
      "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"
    else
      "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
    end
  end

  def status_text
    case processing_status
    when "completed"
      "#{company.linkedin_internal_profile_count || 0} profiles found"
    when "error"
      "Error: #{company.linkedin_internal_error_message}"
    when "processing"
      "Processing..."
    else
      "Not processed"
    end
  end

  def job_in_queue?
    # Check if there's a job in Sidekiq queue for this company
    Sidekiq::Queue.new("linkedin_discovery_internal").any? do |job|
      job.args.first == company.id
    end
  rescue StandardError
    false
  end

  def last_processed_text
    return "Never" unless company.linkedin_internal_last_processed_at
    
    "#{time_ago_in_words(company.linkedin_internal_last_processed_at)} ago"
  end

  def prefilled_sales_navigator_url
    company.linkedin_internal_sales_navigator_url.presence || 
      "https://www.linkedin.com/sales/search/people?query=(spellCorrectionEnabled%3Atrue%2CrecentSearchParam%3A(id%3A4876827156%2CdoLogHistory%3Atrue)%2Cfilters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3Aurn%253Ali%253Aorganization%253A3341537%2Ctext%3ACrowe%2520Norway%2CselectionType%3AINCLUDED%2Cparent%3A(id%3A0)))))%2Ckeywords%3ACrowe%2520Norway)&sessionId=dWkpYPKRTAWlvuhxhajbdQ%3D%3D"
  end

  def can_process?
    !job_in_queue? && processing_status != "processing"
  end
end