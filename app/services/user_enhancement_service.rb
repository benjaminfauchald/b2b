class UserEnhancementService < ApplicationService
  def initialize(attributes = {})
    super(service_name: 'user_enhancement', action: 'enhance', **attributes)
  end

  def call
    return unless service_active?

    users_to_process = @users || User.where('last_enhanced_at IS NULL OR last_enhanced_at < ?', 1.day.ago)
    
    if users_to_process.respond_to?(:find_each)
      users_to_process.find_each(batch_size: batch_size) do |user|
        process_user(user)
      end
    else
      users_to_process.each do |user|
        process_user(user)
      end
    end
  rescue StandardError => e
    log_error(e)
    raise e
  end

  private

  def process_user(user)
    audit_service_operation(user) do |audit_log|
      enhance_user(user, audit_log)
    end
  rescue StandardError => e
    log_error(e, context: { user_id: user.id, email: user.email })
    raise e
  end

  def enhance_user(user, audit_log = nil)
    audit_log = ServiceAuditLog.create!(
      service_name: service_name,
      action: action,
      status: :pending,
      auditable: user,
      started_at: Time.current
    )

    begin
      context = {
        'name_length' => user.name&.length,
        'name_words' => user.name&.split&.count
      }

      if user.email.present?
        domain = user.email.split('@').last
        context.merge!(
          'email_domain' => domain,
          'email_provider' => classify_email_provider(domain)
        )
      end

      audit_log.mark_success!(context)
      user.update!(last_enhanced_at: Time.current)
    rescue StandardError => e
      audit_log.mark_failed!(e.message, context)
      raise
    end
  end

  def classify_email_provider(domain)
    case domain.downcase
    when /gmail\.com$/, /googlemail\.com$/
      'Google'
    when /yahoo\./
      'Yahoo'
    when /hotmail\.com$/, /outlook\.com$/, /live\.com$/
      'Microsoft'
    when /icloud\.com$/, /me\.com$/, /mac\.com$/
      'Apple'
    else
      'Other'
    end
  end

  def service_active?
    ServiceConfiguration.active?(service_name)
  end
end 