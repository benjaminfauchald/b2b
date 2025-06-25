require "ostruct"
require "net/http"
require "json"
require "uri"
require "google/apis/customsearch_v1"
require "openai"

class CompanyWebDiscoveryService < ApplicationService
  def initialize(company_id:, **options)
    @company = Company.find(company_id)
    super(service_name: "company_web_discovery", action: "discover", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?

    # Check if update is needed before starting audit
    unless needs_update?
      # Create a simple audit log for the up-to-date case
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "company_web_discovery",
        operation_type: "discover",
        status: :success,
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: [ "none" ],
        metadata: { reason: "up_to_date", skipped: true },
        started_at: Time.current,
        completed_at: Time.current
      )
      return success_result("Web discovery data is up to date")
    end

    audit_service_operation(@company) do |audit_log|
      # Search for web pages related to the company
      discovered_pages = discover_web_pages

      if discovered_pages.any?
        # Store the discovered pages
        update_company_web_pages(discovered_pages)

        # Add metadata for successful discovery
        audit_log.add_metadata(
          pages_found: discovered_pages.size,
          confidence_scores: discovered_pages.map { |p| p[:confidence] }
        )

        success_result("Web pages discovered", discovered_pages: discovered_pages)
      else
        # No pages found but not an error
        audit_log.add_metadata(pages_found: 0)
        success_result("No websites found for company")
      end
    end
  rescue StandardError => e
    # For rate limit errors, include retry_after in the result data
    if e.message.include?("rate limit") && e.respond_to?(:retry_after)
      error_result(e.message, retry_after: e.retry_after)
    else
      error_result("Service error: #{e.message}")
    end
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "company_web_discovery")
    return false unless config
    config.active?
  end

  def needs_update?
    @company.needs_service?("company_web_discovery")
  end

  def discover_web_pages
    Rails.logger.info "Starting web discovery for: #{@company.company_name}"

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
      if valid_company_website?(result[:url])
        validated = validate_and_score_website(result)
        validated_results << validated if validated
      end
    end

    # Sort by confidence score
    validated_results.sort_by { |r| -r[:confidence] }
  end

  def generate_search_queries
    queries = []

    # Clean company name by removing legal and geographical suffixes
    clean_name = clean_company_name(@company.company_name)

    # Primary search queries using cleaned name
    queries << "#{clean_name} official website"
    queries << "#{clean_name} Norway"
    queries << "#{clean_name} Norge"
    queries << "#{clean_name} company"

    # Also try with original name as fallback
    queries << "#{@company.company_name} official website"

    # Industry-specific search if available
    if @company.primary_industry_description.present?
      queries << "#{clean_name} #{@company.primary_industry_description}"
    end

    # Location-specific search if available
    if @company.business_city.present?
      queries << "#{clean_name} #{@company.business_city}"
    end

    queries.uniq
  end

  def clean_company_name(company_name)
    # Remove legal entity suffixes (Norwegian)
    name = company_name
      .gsub(/\s+(AS|ASA|SA|DA|ANS|BA|NUF|ENK|KS|AL|BBL)$/i, "")

    # Remove geographical suffixes that are commonly added for clarity
    name = name
      .gsub(/\s+(NORWAY|NORGE|NORDIC|SCANDINAVIA|SCANDINAVIAN)$/i, "")
      .gsub(/\s+(EUROPE|EUROPEAN|INTERNATIONAL|GLOBAL)$/i, "")

    # Remove common business descriptors that might not be part of brand name
    name = name
      .gsub(/\s+(GROUP|GRUPPEN|HOLDING|INVEST|INVESTMENT)$/i, "")

    # Clean up multiple spaces and trim
    name.gsub(/\s+/, " ").strip
  end

  def google_search(query)
    unless google_api_configured?
      Rails.logger.info "Google API not configured, returning empty results"
      return []
    end

    Rails.logger.info "Google search for: #{query}"

    begin
      search = Google::Apis::CustomsearchV1::CustomSearchAPIService.new
      search.key = ENV["GOOGLE_SEARCH_API_KEY"]

      response = search.list_cses(
        q: query,
        cx: ENV["GOOGLE_SEARCH_ENGINE_WEB_ID"],
        num: 10,
        safe: "active"
      )

      return [] unless response&.items

      # Filter and map results
      response.items.filter_map do |item|
        # Skip social media and directory sites
        next if skip_domain?(item.link)

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
      error.define_singleton_method(:retry_after) { 3600 }
      raise error
    rescue StandardError => e
      Rails.logger.error "Google search error: #{e.message}"
      # Re-raise for the service to handle
      raise e
    end
  end

  def skip_domain?(url)
    skip_patterns = [
      "facebook.com", "twitter.com", "instagram.com", "youtube.com",
      "linkedin.com", "pinterest.com", "tiktok.com",
      "wikipedia.org", "proff.no", "1881.no", "gulesider.no",
      "yelp.com", "tripadvisor.com"
    ]

    skip_patterns.any? { |pattern| url.include?(pattern) }
  end

  def valid_company_website?(url)
    begin
      uri = URI.parse(url)
      return false unless uri.scheme =~ /^https?$/
      return false unless uri.host

      # Quick HTTP check
      response = HTTParty.head(url,
        timeout: 5,
        follow_redirects: true,
        max_redirects: 3
      )

      response.success?
    rescue StandardError => e
      Rails.logger.debug "URL validation failed for #{url}: #{e.message}"
      false
    end
  end

  def validate_and_score_website(result)
    url = result[:url]

    begin
      # Fetch page content
      response = HTTParty.get(url,
        timeout: 10,
        follow_redirects: true,
        max_redirects: 3,
        headers: {
          "User-Agent" => "Mozilla/5.0 (compatible; CompanyWebDiscovery/1.0)"
        }
      )

      return nil unless response.success?

      # Parse HTML
      doc = Nokogiri::HTML(response.body)

      # Extract metadata
      page_title = doc.at_css("title")&.text&.strip || ""
      meta_description = doc.at_css('meta[name="description"]')&.attr("content") || ""

      # Check if content matches company using AI
      confidence = calculate_confidence_score(
        url: url,
        title: page_title,
        description: meta_description,
        content: extract_text_content(doc),
        search_result: result
      )

      {
        url: url,
        title: page_title,
        description: meta_description,
        confidence: confidence,
        discovered_at: Time.current.iso8601,
        validation_method: "google_search_ai_validation",
        search_query: result[:search_query]
      }
    rescue StandardError => e
      Rails.logger.error "Website validation error for #{url}: #{e.message}"
      nil
    end
  end

  def extract_text_content(doc)
    # Remove script and style elements
    doc.css("script, style").remove

    # Extract text from main content areas
    content_selectors = [
      "main", "article", '[role="main"]',
      ".content", "#content", ".main-content",
      "body"
    ]

    content = nil
    content_selectors.each do |selector|
      element = doc.at_css(selector)
      if element
        content = element.text.squeeze(" ").strip
        break if content.length > 100
      end
    end

    # Limit content length for AI processing
    content&.slice(0, 2000) || ""
  end

  def calculate_confidence_score(data)
    return 70 unless openai_configured?

    begin
      client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

      prompt = build_validation_prompt(data)

      response = client.chat(
        parameters: {
          model: "gpt-3.5-turbo",
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.1,
          max_tokens: 200
        }
      )

      content = response.dig("choices", 0, "message", "content") || ""
      parse_confidence_from_response(content)
    rescue StandardError => e
      Rails.logger.error "OpenAI validation error: #{e.message}"
      # Fallback to basic scoring
      basic_confidence_score(data)
    end
  end

  def build_validation_prompt(data)
    <<~PROMPT
      Validate if this website belongs to the Norwegian company and assign a confidence score.

      Company Information:
      - Name: #{@company.company_name}
      - Industry: #{@company.primary_industry_description || 'Unknown'}
      - Location: #{@company.business_city}, Norway
      - Organization Type: #{@company.organization_form_description || 'Unknown'}

      Website Information:
      - URL: #{data[:url]}
      - Title: #{data[:title]}
      - Description: #{data[:description]}
      - Content Preview: #{data[:content].slice(0, 500)}

      Question: Does this website belong to or represent this Norwegian company?

      Consider:
      1. Company name match in title/content
      2. Industry/business alignment
      3. Geographic relevance (Norwegian company)
      4. Domain name relevance

      Respond with:
      MATCH: Yes/No
      CONFIDENCE: [0-100]
      REASONING: [Brief explanation]
    PROMPT
  end

  def parse_confidence_from_response(response)
    match = response.match(/CONFIDENCE:\s*(\d+)/i)
    confidence = match ? match[1].to_i : 70

    # Check if it's a match
    is_match = response.match(/MATCH:\s*Yes/i)

    # If not a match, cap confidence at 40
    is_match ? confidence : [ confidence, 40 ].min
  end

  def basic_confidence_score(data)
    score = 50
    company_name = @company.company_name.downcase
    clean_name = clean_company_name(@company.company_name).downcase
    
    # Check URL with both original and cleaned names
    url_lower = data[:url].downcase
    if url_lower.include?(clean_name.gsub(/\s+/, "")) || url_lower.include?(company_name.gsub(/\s+/, ""))
      score += 20
    end

    # Check title with both names
    title_lower = data[:title].downcase
    if title_lower.include?(clean_name) || title_lower.include?(company_name)
      score += 15
    end

    # Check description with both names
    desc_lower = data[:description].downcase
    if desc_lower.include?(clean_name) || desc_lower.include?(company_name)
      score += 10
    end

    # Norwegian domain bonus
    if data[:url].include?(".no")
      score += 5
    end

    [ score, 95 ].min
  end

  def normalize_url(url)
    url.downcase.gsub(/\/$/, "").gsub(/^https?:\/\/(www\.)?/, "https://")
  end

  def google_api_configured?
    ENV["GOOGLE_SEARCH_API_KEY"].present? && ENV["GOOGLE_SEARCH_ENGINE_WEB_ID"].present?
  end

  def openai_configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def update_company_web_pages(discovered_pages)
    # Take the highest confidence URL as the main website
    if discovered_pages.any?
      best_match = discovered_pages.first
      @company.website = best_match[:url] if best_match[:confidence] >= 70
    end

    # Store all discovered pages as array (not JSON string)
    @company.web_pages = discovered_pages
    @company.web_discovery_updated_at = Time.current
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
    OpenStruct.new(
      success?: false,
      message: nil,
      error: message,
      data: data
    )
  end
end
