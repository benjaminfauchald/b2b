require "ostruct"

class PersonEmailExtractionService < ApplicationService
  def initialize(person_id: nil, person: nil, **options)
    @person_id = person_id
    @person = person || (person_id ? Person.find(person_id) : nil)
    super(service_name: "person_email_extraction", action: "extract", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Person not found or not provided") unless @person
    return error_result("Hunter.io API key not configured") unless hunter_api_key.present?

    audit_service_operation(@person) do |audit_log|
      Rails.logger.info "🚀 Starting Hunter.io Email Extraction for #{@person.name}"

      # Extract email using Hunter.io API
      email_result = extract_email_from_hunter_io(@person)

      # Check if there was an error in the extraction
      if email_result[:error_code].present?
        audit_log.add_metadata(
          email_found: false,
          error_code: email_result[:error_code],
          error_details: email_result[:error_details] || email_result[:reason]
        )

        # Don't return here, instead raise an error to be caught by audit_service_operation
        raise StandardError.new(email_result[:reason] || "Hunter.io API error")
      end

      if email_result[:email].present?
        # Update person with discovered email
        update_person_with_email(email_result)

        audit_log.add_metadata(
          email_found: true,
          email: email_result[:email],
          confidence: email_result[:confidence],
          sources: email_result[:sources],
          verification_status: email_result[:verification_status],
          hunter_score: email_result[:hunter_data]&.dig(:score),
          hunter_position: email_result[:hunter_data]&.dig(:position)
        )

        success_result("Email extraction completed via Hunter.io",
                      email: email_result[:email],
                      confidence: email_result[:confidence])
      else
        # Update person with "no email found" metadata
        update_person_with_no_email_found(email_result)

        audit_log.add_metadata(
          email_found: false,
          reason: email_result[:reason] || "Hunter.io found no email for this person"
        )

        success_result("No email found for person via Hunter.io")
      end
    end
  rescue Timeout::Error => e
    error_result("Request timeout: #{e.message}")
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "person_email_extraction")
    return false unless config
    config.active?
  end

  def extract_email_from_hunter_io(person)
    # Validate prerequisites
    domain = extract_domain(person.company&.website)
    return { email: nil, reason: "Company and website required for Hunter.io lookup", error_code: "missing_prerequisites" } unless domain

    first_name, last_name = parse_person_name(person.name)
    return { email: nil, reason: "Valid first and last name required for Hunter.io lookup", error_code: "invalid_name_format" } unless first_name && last_name

    # Prepare Hunter.io API request
    params = {
      query: {
        domain: domain,
        first_name: first_name,
        last_name: last_name,
        api_key: hunter_api_key
      },
      timeout: 30
    }

    Rails.logger.info "🔍 Querying Hunter.io for #{first_name} #{last_name} at #{domain}"

    # Make API request
    response = HTTParty.get("https://api.hunter.io/v2/email-finder", params)

    # Handle API response
    if response.success?
      process_hunter_response(response.parsed_response, person)
    else
      handle_hunter_error(response)
    end
  rescue JSON::ParserError => e
    { email: nil, reason: "Invalid response format from Hunter.io: #{e.message}", error_code: "json_parse_error" }
  rescue Timeout::Error => e
    raise e # Re-raise timeout to be handled by the main rescue block
  rescue => e
    { email: nil, reason: "Hunter.io API request failed: #{e.message}", error_code: "api_request_error" }
  end

  def hunter_api_key
    ENV["HUNTER_API_KEY"]
  end

  def parse_person_name(full_name)
    return nil unless full_name.present?

    # Clean and split name, removing titles and suffixes
    cleaned_name = full_name.gsub(/\b(Dr|Mr|Mrs|Ms|Prof|Jr|Sr|III|II)\b\.?/i, "").strip
    parts = cleaned_name.split(/\s+/)

    return nil if parts.length < 2

    first_name = parts.first
    last_name = parts.last

    [ first_name, last_name ]
  end

  def process_hunter_response(hunter_data, person)
    # Ensure hunter_data is a hash
    unless hunter_data.is_a?(Hash)
      return { email: nil, reason: "Invalid response format from Hunter.io", error_code: "invalid_response_format" }
    end

    data = hunter_data["data"]
    return { email: nil, reason: "Hunter.io returned no data" } unless data

    email = data["email"]
    return { email: nil, reason: "Hunter.io found no email for this person" } unless email.present?

    # Extract Hunter.io metadata
    hunter_metadata = {
      score: data["score"],
      domain: data["domain"],
      accept_all: data["accept_all"],
      position: data["position"],
      company: data["company"],
      sources: data["sources"] || [],
      verification: data["verification"] || {}
    }

    verification_status = data.dig("verification", "status") || "unknown"

    {
      email: email,
      confidence: data["score"] || 0,
      verification_status: verification_status,
      sources: [ "hunter_io" ],
      hunter_data: hunter_metadata
    }
  end

  def handle_hunter_error(response)
    error_data = response.parsed_response

    if error_data.is_a?(Hash) && error_data["errors"]
      error = error_data["errors"].first
      error_code = error["code"] || response.code
      error_details = error["details"] || error["id"] || "Unknown error"

      {
        email: nil,
        reason: "Hunter.io API error (#{error_code}): #{error_details}",
        error_code: error_code,
        error_details: error_details
      }
    else
      {
        email: nil,
        reason: "Hunter.io API error (#{response.code}): #{response.message}",
        error_code: response.code
      }
    end
  end

  def generate_company_email(person)
    return { email: nil, confidence: 0, sources: [], verification_status: "not_found" } unless person.company&.website.present?

    # Extract domain from company website
    domain = extract_domain(person.company.website)
    return { email: nil, confidence: 0, sources: [], verification_status: "not_found" } unless domain

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
      sources: [ "company_domain_pattern", "email_verification" ],
      verification_status: confidence > 80 ? "verified" : "probable",
      pattern_used: "first.last@domain"
    }
  end

  def generate_public_profile_email(person)
    # Simulate finding email in public profiles, GitHub, etc.
    domains = [ "gmail.com", "outlook.com", "hotmail.com", "yahoo.com", "icloud.com" ]
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    email = "#{first_name}.#{last_name}@#{domains.sample}"
    confidence = rand(60..85)

    {
      email: email,
      confidence: confidence,
      sources: [ "public_profile", "linkedin_profile", "github_profile" ].sample(2),
      verification_status: confidence > 75 ? "verified" : "unverified",
      profile_source: "LinkedIn"
    }
  end

  def generate_social_media_email(person)
    # Simulate discovery through social media cross-referencing
    domains = [ "gmail.com", "outlook.com", "yahoo.com" ]
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    email = "#{first_name}#{last_name}#{rand(10..99)}@#{domains.sample}"
    confidence = rand(50..75)

    {
      email: email,
      confidence: confidence,
      sources: [ "twitter_profile", "facebook_profile", "instagram_discovery" ].sample(1),
      verification_status: "unverified",
      social_platform: [ "Twitter", "Facebook", "Instagram" ].sample
    }
  end

  def generate_database_email(person)
    # Simulate finding in contact databases like ZoomInfo, Apollo, etc.
    domain = person.company&.website ? extract_domain(person.company.website) : "company.com"
    first_name = person.name.split.first&.downcase
    last_name = person.name.split.last&.downcase

    email = "#{first_name}.#{last_name}@#{domain}"
    confidence = rand(85..98)

    {
      email: email,
      confidence: confidence,
      sources: [ "contact_database", "zoominfo", "apollo_io" ],
      verification_status: "verified",
      database_source: [ "ZoomInfo", "Apollo.io", "Clearbit" ].sample
    }
  end

  def extract_domain(website_url)
    return nil unless website_url.present?

    # Clean and extract domain
    url = website_url.gsub(/^https?:\/\//, "").gsub(/^www\./, "").split("/").first
    url&.downcase
  end

  def update_person_with_email(email_result)
    email_data = {
      email: email_result[:email],
      confidence: email_result[:confidence],
      extracted_at: Time.current,
      source: "hunter_io",
      verification_status: email_result[:verification_status],
      sources: email_result[:sources],
      hunter_data: email_result[:hunter_data] || {}
    }

    @person.update!(
      email: email_result[:email],
      email_extracted_at: Time.current,
      email_data: email_data
    )

    Rails.logger.info "📧 Updated person with Hunter.io email: #{email_result[:email]} (#{email_result[:confidence]}% confidence)"
  end

  def update_person_with_no_email_found(email_result)
    email_data = {
      email: nil,
      confidence: 0,
      extracted_at: Time.current,
      source: "hunter_io",
      verification_status: "not_found",
      sources: [ "hunter_io" ],
      reason: email_result[:reason] || "Hunter.io found no email for this person",
      hunter_data: email_result[:hunter_data] || {}
    }

    @person.update!(
      email_extracted_at: Time.current,
      email_data: email_data
    )

    Rails.logger.info "📧 Updated person with Hunter.io 'no email found' result: #{email_result[:reason]}"
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
