# frozen_string_literal: true

# LinkedIn Company Data Button Component
# Provides a button to extract LinkedIn company data with real-time status updates
class LinkedinCompanyDataButtonComponent < ViewComponent::Base
  attr_reader :company, :button_text, :button_class, :size, :turbo_frame_id

  def initialize(company:, button_text: "Extract LinkedIn Data", button_class: "btn-primary", size: "sm", turbo_frame_id: nil)
    @company = company
    @button_text = button_text
    @button_class = button_class
    @size = size
    @turbo_frame_id = turbo_frame_id || "linkedin_company_data_frame_#{company.id}"
  end

  def render?
    company.present? && service_available?
  end

  private

  def service_available?
    config = ServiceConfiguration.find_by(service_name: 'linkedin_company_data')
    config&.active?
  end

  def queue_path
    queue_linkedin_company_data_company_path(company)
  end

  def status_class
    case service_status
    when 'success'
      'text-success'
    when 'failed'
      'text-danger'
    when 'processing'
      'text-warning'
    else
      'text-muted'
    end
  end

  def service_status
    # Check recent audit log for this company
    recent_log = ServiceAuditLog.where(
      service_name: 'linkedin_company_data',
      auditable: company
    ).order(created_at: :desc).first

    return 'unknown' unless recent_log

    case recent_log.status
    when 'success'
      'success'
    when 'failed'
      'failed'
    when 'pending', 'in_progress'
      'processing'
    else
      'unknown'
    end
  end

  def button_icon
    case service_status
    when 'success'
      '<i class="fas fa-check-circle"></i>'.html_safe
    when 'failed'
      '<i class="fas fa-exclamation-triangle"></i>'.html_safe
    when 'processing'
      '<i class="fas fa-spinner fa-spin"></i>'.html_safe
    else
      '<i class="fab fa-linkedin"></i>'.html_safe
    end
  end

  def button_disabled?
    service_status == 'processing'
  end

  def last_extraction_info
    recent_log = ServiceAuditLog.where(
      service_name: 'linkedin_company_data',
      auditable: company,
      status: 'success'
    ).order(created_at: :desc).first

    return nil unless recent_log

    {
      extracted_at: recent_log.completed_at,
      company_name: recent_log.metadata&.dig('company_name'),
      linkedin_id: recent_log.metadata&.dig('company_id'),
      execution_time: recent_log.execution_time_ms
    }
  end
end