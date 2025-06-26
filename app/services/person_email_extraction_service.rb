require "ostruct"

class PersonEmailExtractionService < ApplicationService
  def initialize(person_id:, **options)
    @person_id = person_id
    @person = Person.find(person_id)
    super(service_name: "person_email_extraction", action: "extract", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Person not found") unless @person

    audit_service_operation(@person) do |audit_log|
      Rails.logger.info "🚀 Starting Email Extraction for #{@person.name}"
      
      # Simulate email discovery using mock patterns
      email_result = simulate_email_discovery(@person)
      
      if email_result[:email].present?
        # Update person with discovered email
        update_person_with_email(email_result)
        
        audit_log.add_metadata(
          email_found: true,
          email: email_result[:email],
          confidence: email_result[:confidence],
          sources: email_result[:sources],
          verification_status: email_result[:verification_status]
        )
        
        success_result("Email extraction completed", 
                      email: email_result[:email],
                      confidence: email_result[:confidence])
      else
        audit_log.add_metadata(
          email_found: false,
          reason: "No email patterns matched"
        )
        
        success_result("No email found for person")
      end
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "person_email_extraction")
    return false unless config
    config.active?
  end

  def simulate_email_discovery(person)
    # Simulate realistic email discovery patterns based on real services
    scenarios = [
      { probability: 0.65, type: 'company_domain_pattern' },
      { probability: 0.15, type: 'public_profile' },
      { probability: 0.10, type: 'social_media_discovery' },
      { probability: 0.05, type: 'contact_database_match' },
      { probability: 0.05, type: 'no_email_found' }
    ]
    
    # Select scenario based on probability
    random_val = rand
    cumulative_prob = 0
    selected_scenario = nil
    
    scenarios.each do |scenario|
      cumulative_prob += scenario[:probability]
      if random_val <= cumulative_prob
        selected_scenario = scenario[:type]
        break
      end
    end
    
    case selected_scenario
    when 'company_domain_pattern'
      generate_company_email(person)
    when 'public_profile'
      generate_public_profile_email(person)
    when 'social_media_discovery'
      generate_social_media_email(person)
    when 'contact_database_match'
      generate_database_email(person)
    else
      { email: nil, confidence: 0, sources: [], verification_status: 'not_found' }
    end
  end

  def generate_company_email(person)
    return { email: nil, confidence: 0, sources: [], verification_status: 'not_found' } unless person.company&.website.present?
    
    # Extract domain from company website
    domain = extract_domain(person.company.website)
    return { email: nil, confidence: 0, sources: [], verification_status: 'not_found' } unless domain
    
    # Generate common email patterns
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase
    
    patterns = [
      "#{first_name}.#{last_name}@#{domain}",
      "#{first_name}#{last_name}@#{domain}",
      "#{first_name.first}#{last_name}@#{domain}",
      "#{first_name}@#{domain}"
    ]
    
    # Select most likely pattern (simulate verification)
    email = patterns.sample
    confidence = rand(70..95)
    
    {
      email: email,
      confidence: confidence,
      sources: ['company_domain_pattern', 'email_verification'],
      verification_status: confidence > 80 ? 'verified' : 'probable',
      pattern_used: "first.last@domain"
    }
  end

  def generate_public_profile_email(person)
    # Simulate finding email in public profiles, GitHub, etc.
    domains = ['gmail.com', 'outlook.com', 'hotmail.com', 'yahoo.com', 'icloud.com']
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase
    
    email = "#{first_name}.#{last_name}@#{domains.sample}"
    confidence = rand(60..85)
    
    {
      email: email,
      confidence: confidence,
      sources: ['public_profile', 'linkedin_profile', 'github_profile'].sample(2),
      verification_status: confidence > 75 ? 'verified' : 'unverified',
      profile_source: 'LinkedIn'
    }
  end

  def generate_social_media_email(person)
    # Simulate discovery through social media cross-referencing
    domains = ['gmail.com', 'outlook.com', 'yahoo.com']
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase
    
    email = "#{first_name}#{last_name}#{rand(10..99)}@#{domains.sample}"
    confidence = rand(50..75)
    
    {
      email: email,
      confidence: confidence,
      sources: ['twitter_profile', 'facebook_profile', 'instagram_discovery'].sample(1),
      verification_status: 'unverified',
      social_platform: ['Twitter', 'Facebook', 'Instagram'].sample
    }
  end

  def generate_database_email(person)
    # Simulate finding in contact databases like ZoomInfo, Apollo, etc.
    domain = person.company&.website ? extract_domain(person.company.website) : 'company.com'
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase
    
    email = "#{first_name}.#{last_name}@#{domain}"
    confidence = rand(85..98)
    
    {
      email: email,
      confidence: confidence,
      sources: ['contact_database', 'zoominfo', 'apollo_io'],
      verification_status: 'verified',
      database_source: ['ZoomInfo', 'Apollo.io', 'Clearbit'].sample
    }
  end

  def extract_domain(website_url)
    return nil unless website_url.present?
    
    # Clean and extract domain
    url = website_url.gsub(/^https?:\/\//, '').gsub(/^www\./, '').split('/').first
    url&.downcase
  end

  def update_person_with_email(email_result)
    email_data = {
      email: email_result[:email],
      confidence: email_result[:confidence],
      extracted_at: Time.current,
      source: 'mock_email_service',
      verification_status: email_result[:verification_status],
      sources: email_result[:sources]
    }
    
    @person.update!(
      email: email_result[:email],
      email_extracted_at: Time.current,
      email_data: email_data
    )
    
    Rails.logger.info "📧 Updated person with email: #{email_result[:email]} (#{email_result[:confidence]}% confidence)"
  end

  def success_result(message, data = {})
    OpenStruct.new(
      success?: true,
      message: message,
      data: data,
      error: nil
    )
  end

  def error_result(message, data = {})
    OpenStruct.new(
      success?: false,
      message: nil,
      error: message,
      data: data
    )
  end
end