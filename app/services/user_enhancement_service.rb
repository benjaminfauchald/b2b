class UserEnhancementService < ApplicationService
  def initialize(attributes = {})
    super(service_name: 'user_enhancement_service', action: 'enhance', **attributes)
  end
  
  private
  
  def perform
    users_needing_enhancement = User.needing_service(service_name)
    puts "[DEBUG] UserEnhancementService processing user IDs: #{users_needing_enhancement.map(&:id)}"
    
    if users_needing_enhancement.empty?
      puts "No users need enhancement at this time."
      return
    end
    
    batch_process(users_needing_enhancement) { |user, audit_log| enhance_user(user, audit_log) }
  end
  
  def enhance_user(user, audit_log)
    # Track original values
    original_attributes = user.attributes.dup
    
    # Example enhancements
    enhanced_data = {}
    
    # Enhance email domain if present
    if user.email.present?
      domain = user.email.split('@').last
      enhanced_data[:email_domain] = domain
      enhanced_data[:email_provider] = classify_email_provider(domain)
    end
    
    # Enhance name if present
    if user.name.present?
      enhanced_data[:name_length] = user.name.length
      enhanced_data[:name_words] = user.name.split.length
    end
    
    # Store enhancement data in audit log context
    audit_log.add_context(enhanced_data)
    
    # Track what fields we "enhanced" (in this example, we're not actually updating the user)
    # In a real implementation, you might update calculated fields, scores, etc.
    audit_log.track_changes(user) if user.changed?
    
    # Mark success with enhancement context
    audit_log.mark_success!(enhanced_data)
    
  rescue StandardError => e
    audit_log.mark_failed!(e.message, { 'error_type' => e.class.name })
    raise
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
end 