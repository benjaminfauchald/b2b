# Bug fix for LinkedIn discovery service - testing non-blocking IDM
# Feature tracked by IDM: feature_memories/linkedin_discovery_bug_fix.rb
require "ostruct"
# Fixed require statements order
require "net/http"
require "json"
require "uri"
require "google/apis/customsearch_v1"
require "openai"

class CompanyLinkedinDiscoveryService < ApplicationService
  def initialize(company_id: nil, company: nil, **options)
    @company = company || (company_id ? Company.find(company_id) : nil)
    super(service_name: "company_linkedin_discovery", action: "discover", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Company not found or not provided") unless @company

    # Check if update is needed before starting audit
    unless needs_update?
      # Create a simple audit log for the up-to-date case
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "company_linkedin_discovery",
        operation_type: "discover",
        status: :skipped,
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: [ "none" ],
        metadata: { reason: "up_to_date", skipped: true },
        started_at: Time.current,
        completed_at: Time.current
      )
      return success_result("LinkedIn discovery data is up to date")
    end

    audit_service_operation(@company) do |audit_log|
      # Search for LinkedIn profiles related to the company
      discovered_profiles = discover_linkedin_profiles

      # Always update company data (even with empty results to mark as processed)
      update_company_linkedin_data(discovered_profiles)

      if discovered_profiles.any?
        # Add metadata for successful discovery
        highest_confidence = discovered_profiles.first[:confidence] rescue 0
        low_confidence = highest_confidence < 50
        audit_log.add_metadata(
          profiles_found: discovered_profiles.size,
          highest_confidence: highest_confidence,
          low_confidence: low_confidence,
          confidence_scores: discovered_profiles.map { |p| p[:confidence] },
          discovered_profiles: discovered_profiles,
          best_match: discovered_profiles.first,
          discovery_timestamp: Time.current.iso8601
        )

        # Check if the best match has low confidence
        if discovered_profiles.first[:confidence] < 50
          success_result("Low confidence matches found for LinkedIn discovery", linkedin_profiles: discovered_profiles)
        else
          success_result("LinkedIn profiles discovered", linkedin_profiles: discovered_profiles)
        end
      else
        # No profiles found but not an error
        audit_log.add_metadata(profiles_found: 0)
        success_result("No LinkedIn profiles found for company")
      end
    end
  rescue StandardError => e
    # For rate limit errors, include retry_after in the result data
    if e.message.include?("rate limit") && e.respond_to?(:retry_after)
      error_result(e.message, { retry_after: e.retry_after })
    else
      error_result("Service error: #{e.message}")
    end
  end

  private

  def generic_industry?(industry_description)
    return false if industry_description.blank?
    
    # List of generic industry terms that don't help LinkedIn searches
    generic_terms = [
      'business services', 'consulting', 'management', 'advisory services',
      'commercial services', 'professional services', 'general business',
      'other business activities', 'administration', 'support activities',
      'wholesale', 'retail', 'trading', 'import', 'export'
    ]
    
    industry_lower = industry_description.downcase.strip
    generic_terms.any? { |term| industry_lower.include?(term) }
  end

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "company_linkedin_discovery")
    return false unless config
    config.active?
  end

  def needs_update?
    @company.needs_service?("company_linkedin_discovery")
  end

  def discover_linkedin_profiles
    Rails.logger.info "Starting LinkedIn discovery for: #{@company.company_name}"

    # Generate search queries
    search_queries = generate_search_queries

    # Search using Google Custom Search API
    all_results = []
    search_queries.each do |query|
      results = google_search(query)
      all_results.concat(results) if results
    end

    # Remove duplicates by URL
    unique_results = all_results.uniq { |r| normalize_url(r[:url]) }

    # Validate and score each result
    validated_results = []
    unique_results.each do |result|
      if valid_linkedin_profile?(result[:url])
        validated = validate_and_score_linkedin_profile(result)
        # Store ALL validated results (including low confidence ones)
        # Store ALL validated results (including low confidence ones)
        if validated
          validated_results << validated
        end      end
    end

    # Sort by confidence score
    validated_results.sort_by { |r| -r[:confidence] }
  end

  def generate_search_queries
    queries = []

    # Base company name without legal suffixes
    base_name = @company.company_name
      .gsub(/\s+(AS|ASA|SA|DA|ANS|BA|NUF|ENK|KS|AL|BBL)$/i, "")
      .strip

    # Primary search queries for LinkedIn
    queries << "#{@company.company_name} site:linkedin.com"
    
    # Only add base name query if different from company name (has legal suffix)
    if base_name != @company.company_name
      queries << "#{base_name} Norge site:linkedin.com"
    end

    # Industry-specific search if available and not too generic
    if @company.primary_industry_description.present? && !generic_industry?(@company.primary_industry_description)
      queries << "#{base_name} #{@company.primary_industry_description} site:linkedin.com"
    end

    # Location-specific search if available
    if @company.business_city.present?
      queries << "#{base_name} #{@company.business_city} site:linkedin.com"
    end

    queries.uniq
  end

  def google_search(query)
    unless google_api_configured?
      Rails.logger.info "Google API not configured, returning empty results"
      return []
    end

    Rails.logger.info "Google search for LinkedIn profiles: #{query}"

    begin
      search = Google::Apis::CustomsearchV1::CustomSearchAPIService.new
      search.key = ENV["GOOGLE_SEARCH_API_KEY"]

      response = search.list_cses(
        q: query,
        cx: ENV["GOOGLE_SEARCH_ENGINE_LINKED_IN_COMPANIES_NO_ID"],
        num: 10,
        safe: "active"
      )

      return [] unless response&.items

      # Filter and map results
      response.items.filter_map do |item|
        # Only include LinkedIn URLs
        next unless item.link.include?("linkedin.com")

        {
          url: item.link,
          title: item.title,
          snippet: item.snippet,
          search_query: query
        }
      end
    rescue Google::Apis::RateLimitError => e
      Rails.logger.warn "Google API rate limit hit"
      error = StandardError.new("API rate limit exceeded")
      error.define_singleton_method(:retry_after) { 7200 }  # Match test expectation of 2 hours
      raise error
    rescue StandardError => e
      Rails.logger.error "Google search error: #{e.message}"
      # Re-raise with a more specific message for LinkedIn API errors
      if e.message.include?("Server error") || e.message.include?("API Error")
        raise StandardError.new("LinkedIn API error: #{e.message}")
      else
        raise e
      end
    end
  end

  def valid_linkedin_profile?(url)
    begin
      uri = URI.parse(url)
      return false unless uri.scheme =~ /^https?$/
      return false unless uri.host&.include?("linkedin.com")

      # ONLY allow company pages - no personal profiles or other types
      url.include?("/company/") || url.include?("/showcase/")

    rescue StandardError => e
      Rails.logger.debug "LinkedIn URL validation failed for #{url}: #{e.message}"
      false
    end
  end

  def validate_and_score_linkedin_profile(result)
    url = result[:url]

    begin
      # For LinkedIn, we primarily rely on URL pattern matching and title/snippet analysis
      # since LinkedIn blocks most scraping attempts

      # Extract LinkedIn profile type
      profile_type = extract_linkedin_profile_type(url)

      # Check if content matches company using AI
      confidence = calculate_confidence_score(
        url: url,
        title: result[:title],
        description: result[:snippet],
        content: result[:snippet], # Use snippet as content for LinkedIn
        search_result: result,
        profile_type: profile_type
      )

      {
        url: url,
        title: result[:title],
        description: result[:snippet],
        confidence: confidence,
        profile_type: profile_type,
        discovered_at: Time.current.iso8601,
        validation_method: "google_search_ai_validation",
        search_query: result[:search_query]
      }
    rescue StandardError => e
      Rails.logger.error "LinkedIn profile validation error for #{url}: #{e.message}"
      nil
    end
  end

  def extract_linkedin_profile_type(url)
    if url.include?("/company/")
      "company"
    elsif url.include?("/showcase/")
      "showcase"
    elsif url.include?("/in/")
      "personal"
    elsif url.include?("/school/")
      "school"
    else
      "unknown"
    end
  end

  def calculate_confidence_score(data)
    unless openai_configured?
      Rails.logger.warn "OpenAI not configured, using basic confidence scoring"
      return basic_confidence_score(data)
    end

    begin
      # Use Azure OpenAI configuration
      client = OpenAI::Client.new(
        access_token: ENV["AZURE_OPENAI_API_KEY"],
        uri_base: ENV["AZURE_OPENAI_ENDPOINT"],
        request_timeout: 30,
        extra_headers: {
          "api-key" => ENV["AZURE_OPENAI_API_KEY"]
        }
      )

      prompt = build_validation_prompt(data)

      # Azure OpenAI uses deployment names instead of model names
      response = client.chat(
        parameters: {
          model: ENV["AZURE_OPENAI_API_DEPLOYMENT"] || "gpt-4.1",
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.1,
          max_tokens: 200
        }
      )

      content = response.dig("choices", 0, "message", "content") || ""
      parse_confidence_from_response(content)
    rescue StandardError => e
      Rails.logger.error "Azure OpenAI validation error: #{e.message}"
      # Fallback to basic scoring
      basic_confidence_score(data)
    end
  end

  def build_validation_prompt(data)
    <<~PROMPT
      CRITICAL: You must validate if this LinkedIn profile belongs to the EXACT Norwegian company specified below.
      
      This is NOT about similar companies or companies in the same industry.
      This is about finding the EXACT company match.
      
      TARGET COMPANY (must match exactly):
      - Name: #{@company.company_name}
      - Industry: #{@company.primary_industry_description || 'Unknown'}
      - Location: #{@company.business_city}, Norway
      - Organization Type: #{@company.organization_form_description || 'Unknown'}

      LINKEDIN PROFILE TO VALIDATE:
      - URL: #{data[:url]}
      - Title: #{data[:title]}
      - Description: #{data[:description]}
      - Profile Type: #{data[:profile_type]}

      VALIDATION CRITERIA (ALL must be met for a Yes match):
      1. The LinkedIn profile title/description must contain the EXACT company name or a clear variation
      2. The company name in the profile must match the target company (not just similar)
      3. The profile must be for a Norwegian company (not international subsidiaries with similar names)
      4. The profile must be a company page, not a personal profile
      5. The industry/business must align with the target company
      
      IMPORTANT: If the LinkedIn profile is for a different company with a similar name, answer "No".
      IMPORTANT: If the company name doesn't match exactly, answer "No".
      IMPORTANT: If you're unsure, answer "No".
      
      QUESTION: Is this LinkedIn profile for the EXACT company "#{@company.company_name}"?

      Respond with:
      MATCH: Yes/No
      CONFIDENCE: [0-100]
      REASONING: [Brief explanation of why this is/isn't the exact company]
    PROMPT
  end

  def parse_confidence_from_response(response)
    match = response.match(/CONFIDENCE:\s*(\d+)/i)
    confidence = match ? match[1].to_i : 70

    # Check if it's a match
    is_match = response.match(/MATCH:\s*Yes/i)

    # If AI says it's NOT a match, return 0 confidence (reject it)
    # Only return the confidence score if AI confirms it's a match
    is_match ? confidence : 0
  end

  def basic_confidence_score(data)
    score = 0  # Start at 0 - require strong matches
    company_name = @company.company_name.downcase
    
    # Remove legal suffixes (AS, ASA, DA are Norwegian company types like Ltd/LLC)
    base_name = company_name.gsub(/\s+(as|asa|sa|da|ans|ba|nuf|enk|ks|al|bbl)$/i, "").strip.downcase
    
    # Extract core company name (before geographical descriptors)
    # Common Norwegian geographical terms that indicate subsidiaries/branches
    geographical_terms = GeographicalTerm.subsidiary_indicator_terms('NO')
    
    # Create core name by removing geographical descriptors
    core_name = base_name.dup
    geographical_terms.each do |geo_term|
      core_name = core_name.gsub(/\s+#{geo_term}(?:\s|$)/i, " ").strip
    end
    core_name = core_name.strip
    
    # Create variations for matching
    name_variations = [
      base_name.gsub(/\s+/, ""),           # Full name without spaces
      base_name.gsub(/\s+/, "-"),          # Full name with hyphens
      core_name.gsub(/\s+/, ""),           # Core name without spaces (for subsidiaries)
      core_name.gsub(/\s+/, "-"),          # Core name with hyphens
      base_name,                           # Full name with spaces
      core_name                            # Core name with spaces
    ].uniq.reject(&:empty?)

    # Check URL for company name match (most reliable)
    url_lower = data[:url].downcase
    url_score = 0
    name_variations.each do |variation|
      if variation.length > 3 && url_lower.include?(variation)
        if variation == base_name.gsub(/\s+/, "") || variation == base_name.gsub(/\s+/, "-")
          url_score = 50  # Perfect match for full company name
        else
          url_score = 40  # Good match for core name (subsidiary case)
        end
        break
      end
    end
    score += url_score

    # Check title for company name match
    title_lower = data[:title].downcase
    title_score = 0
    name_variations.each do |variation|
      if variation.length > 3 && title_lower.include?(variation)
        if variation == base_name || variation == base_name.gsub(/\s+/, "")
          title_score = 30  # Perfect match for full company name
        else
          title_score = 25  # Good match for core name
        end
        break
      end
    end
    score += title_score

    # Check description for company name match
    description_lower = data[:description].downcase
    description_score = 0
    name_variations.each do |variation|
      if variation.length > 3 && description_lower.include?(variation)
        description_score = 15  # Any name match in description
        break
      end
    end
    score += description_score

    # Require company profile type (not personal)
    if data[:profile_type] == "company"
      score += 10
    elsif data[:profile_type] == "showcase"
      score += 5
    else
      # Penalize non-company profiles
      score -= 20
    end

    # Industry match bonus if available
    if @company.primary_industry_description.present?
      industry_lower = @company.primary_industry_description.downcase
      if description_lower.include?(industry_lower) || title_lower.include?(industry_lower)
        score += 10
      end
    end

    # Location match bonus if available
    if @company.business_city.present?
      city_lower = @company.business_city.downcase
      if description_lower.include?(city_lower) || title_lower.include?(city_lower)
        score += 10
      end
    end

    # Ensure score is between 0 and 100
    [ [ score, 0 ].max, 100 ].min
  end
  def normalize_url(url)
    url.downcase.gsub(/\/$/, "").gsub(/^https?:\/\/(www\.)?/, "https://")
  end

  def google_api_configured?
    ENV["GOOGLE_SEARCH_API_KEY"].present? && ENV["GOOGLE_SEARCH_ENGINE_LINKED_IN_COMPANIES_NO_ID"].present?
  end

  def openai_configured?
    # Check for either standard OpenAI or Azure OpenAI configuration
    ENV["OPENAI_API_KEY"].present? ||
    (ENV["AZURE_OPENAI_API_KEY"].present? && ENV["AZURE_OPENAI_ENDPOINT"].present?)
  end

  def update_company_linkedin_data(discovered_profiles)
    if discovered_profiles.any?
      best_match = discovered_profiles.first
      
      # Only store the match as main URL if confidence is >= 60%
      if best_match[:confidence] >= 60
        @company.linkedin_ai_url = best_match[:url]
        # Convert confidence to integer if it's a float between 0 and 1
        confidence = best_match[:confidence]
        @company.linkedin_ai_confidence = confidence < 1 ? (confidence * 100).to_i : confidence.to_i
        
        # Update employee count if available in the best match company_info
        if best_match[:company_info] && best_match[:company_info][:employees]
          @company.linkedin_employee_count = best_match[:company_info][:employees]
        end
      else
        # Clear any existing AI URL if new results are low confidence
        @company.linkedin_ai_url = nil
        @company.linkedin_ai_confidence = nil
      end
      
      # Store ALL discovered profiles in linkedin_alternatives (including low confidence ones)
      @company.linkedin_alternatives = discovered_profiles.map do |profile|
        {
          url: profile[:url],
          confidence: profile[:confidence],
          title: profile[:title],
          profile_type: profile[:profile_type]
        }
      end
    else
      # Clear any existing AI URL if no profiles found
      @company.linkedin_ai_url = nil
      @company.linkedin_ai_confidence = nil
      @company.linkedin_alternatives = []
    end

    # Always mark as processed, even if no profiles found
    @company.linkedin_processed = true
    @company.linkedin_last_processed_at = Time.current

    # Save the company updates
    @company.save!
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
    result = OpenStruct.new(
      success?: false,
      message: nil,
      error: message,
      data: data
    )
    # Add retry_after as a direct property if it exists in data
    result.retry_after = data[:retry_after] if data[:retry_after]
    result
  end
end
