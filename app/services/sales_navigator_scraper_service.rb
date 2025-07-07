# frozen_string_literal: true

# Sales Navigator Scraper Service
# Advanced LinkedIn Sales Navigator scraper using Voyager API endpoints
# Based on research: tmp/linkedin_api_research_report.md
class SalesNavigatorScraperService < ApplicationService
  require 'net/http'
  require 'json'
  require 'uri'
  require 'openssl'
  
  attr_reader :session, :csrf_token, :authenticated
  
  def initialize
    super(service_name: "sales_navigator_scraper")
    @base_url = "https://www.linkedin.com"
    @api_base = "#{@base_url}/voyager/api"
    @session = nil
    @csrf_token = nil
    @authenticated = false
    @rate_limiter = RateLimiter.new(max_requests_per_hour: 100)
  end
  
  # Main method to extract profiles from Sales Navigator URL
  def extract_profiles_from_url(sales_navigator_url)
    Rails.logger.info "SalesNavigatorScraper: Starting extraction from #{sales_navigator_url}"
    
    begin
      # Parse the Sales Navigator URL to extract search parameters
      search_params = parse_sales_navigator_url(sales_navigator_url)
      Rails.logger.info "SalesNavigatorScraper: Parsed search params: #{search_params.inspect}"
      
      # Authenticate and setup session
      unless authenticate_with_linkedin
        return error_response("Failed to authenticate with LinkedIn")
      end
      
      # Extract profiles using Voyager API
      result = search_people_via_voyager(search_params)
      
      if result[:success]
        Rails.logger.info "SalesNavigatorScraper: Successfully extracted #{result[:profiles].size} profiles"
        success_response(result)
      else
        Rails.logger.error "SalesNavigatorScraper: Profile extraction failed: #{result[:error]}"
        error_response(result[:error])
      end
      
    rescue => e
      Rails.logger.error "SalesNavigatorScraper: Exception during extraction: #{e.message}"
      Rails.logger.error "SalesNavigatorScraper: #{e.backtrace.first(5).join("\n")}"
      error_response("Extraction failed: #{e.message}")
    end
  end
  
  private
  
  # Parse Sales Navigator URL to extract search parameters
  def parse_sales_navigator_url(url)
    begin
      uri = URI.parse(url)
      query_params = URI.decode_www_form(uri.query || "").to_h
      
      search_params = {
        keywords: nil,
        company_id: nil,
        location: nil,
        count: 25,
        start: 0
      }
      
      # Extract query data from Sales Navigator format
      if query_params["query"].present?
        query_data = query_params["query"]
        Rails.logger.info "SalesNavigatorScraper: Parsing query data: #{query_data}"
        
        # Extract company ID from CURRENT_COMPANY filter
        if query_data.include?("CURRENT_COMPANY")
          company_match = query_data.match(/id[:\s]*([0-9]+)/)
          if company_match
            search_params[:company_id] = company_match[1]
            Rails.logger.info "SalesNavigatorScraper: Found company ID: #{search_params[:company_id]}"
          end
        end
        
        # Extract keywords if present
        if query_data.include?("keywords")
          keywords_match = query_data.match(/keywords[:\s]*([^,)]+)/)
          if keywords_match
            search_params[:keywords] = keywords_match[1].gsub("%20", " ").strip
            Rails.logger.info "SalesNavigatorScraper: Found keywords: #{search_params[:keywords]}"
          end
        end
      end
      
      # Extract sessionId for continuity
      if query_params["sessionId"].present?
        search_params[:session_id] = query_params["sessionId"]
      end
      
      search_params
    rescue => e
      Rails.logger.error "SalesNavigatorScraper: Failed to parse URL: #{e.message}"
      { keywords: nil, company_id: nil, location: nil, count: 25, start: 0 }
    end
  end
  
  # Authenticate with LinkedIn using stored credentials
  def authenticate_with_linkedin
    Rails.logger.info "SalesNavigatorScraper: Starting LinkedIn authentication"
    
    # Try cookie-based authentication first
    if authenticate_with_cookies
      Rails.logger.info "SalesNavigatorScraper: Cookie authentication successful"
      return true
    end
    
    # Fallback to credential-based authentication
    if authenticate_with_credentials
      Rails.logger.info "SalesNavigatorScraper: Credential authentication successful"
      return true
    end
    
    Rails.logger.error "SalesNavigatorScraper: All authentication methods failed"
    false
  end
  
  # Cookie-based authentication (faster)
  def authenticate_with_cookies
    cookies = load_linkedin_cookies
    
    unless cookies['li_at'].present?
      Rails.logger.warn "SalesNavigatorScraper: No LinkedIn session cookie found"
      return false
    end
    
    @session = create_http_session(cookies)
    @csrf_token = extract_csrf_token
    
    # Test authentication with a simple API call
    test_result = test_authentication
    if test_result
      @authenticated = true
      Rails.logger.info "SalesNavigatorScraper: Cookie authentication verified"
      true
    else
      Rails.logger.warn "SalesNavigatorScraper: Cookie authentication failed verification"
      false
    end
  rescue => e
    Rails.logger.error "SalesNavigatorScraper: Cookie authentication error: #{e.message}"
    false
  end
  
  # Credential-based authentication (fallback)
  def authenticate_with_credentials
    email = ENV['LINKEDIN_EMAIL']
    password = ENV['LINKEDIN_PASSWORD']
    
    unless email.present? && password.present?
      Rails.logger.warn "SalesNavigatorScraper: LinkedIn credentials not configured"
      return false
    end
    
    # This would involve logging in via the web interface
    # For now, we'll focus on cookie-based authentication
    Rails.logger.info "SalesNavigatorScraper: Credential authentication not implemented yet"
    false
  end
  
  # Load LinkedIn cookies from environment or file
  def load_linkedin_cookies
    cookies = {}
    
    # Try to load from environment variables
    cookies['li_at'] = ENV['LINKEDIN_COOKIE_LI_AT']
    cookies['JSESSIONID'] = ENV['LINKEDIN_COOKIE_JSESSIONID']
    cookies['li_gc'] = ENV['LINKEDIN_COOKIE_LI_GC']
    cookies['bcookie'] = ENV['LINKEDIN_COOKIE_BCOOKIE']
    cookies['bscookie'] = ENV['LINKEDIN_COOKIE_BSCOOKIE']
    
    # Try to load from saved cookie file
    if cookies['li_at'].blank?
      cookie_file = Rails.root.join('tmp', 'linkedin_cookies.json')
      if File.exist?(cookie_file)
        begin
          saved_cookies = JSON.parse(File.read(cookie_file))
          cookies.merge!(saved_cookies)
          Rails.logger.info "SalesNavigatorScraper: Loaded cookies from file"
        rescue => e
          Rails.logger.warn "SalesNavigatorScraper: Failed to load cookies from file: #{e.message}"
        end
      end
    end
    
    cookies.compact
  end
  
  # Create HTTP session with proper headers and cookies
  def create_http_session(cookies)
    @session = Net::HTTP.new('www.linkedin.com', 443)
    @session.use_ssl = true
    @session.verify_mode = OpenSSL::SSL::VERIFY_PEER
    
    @session_cookies = cookies
    @session_headers = {
      'User-Agent' => linkedin_user_agent,
      'Accept' => 'application/vnd.linkedin.normalized+json+2.1',
      'Accept-Language' => 'en-US,en;q=0.9',
      'Accept-Encoding' => 'gzip, deflate, br',
      'Connection' => 'keep-alive',
      'x-restli-protocol-version' => '2.0.0',
      'x-li-lang' => 'en_US',
      'Sec-Fetch-Dest' => 'empty',
      'Sec-Fetch-Mode' => 'cors',
      'Sec-Fetch-Site' => 'same-origin',
      'Cookie' => format_cookies(cookies)
    }
    
    @session
  end
  
  # Format cookies for HTTP header
  def format_cookies(cookies)
    cookies.map { |name, value| "#{name}=#{value}" }.join('; ')
  end
  
  # Extract CSRF token from LinkedIn page
  def extract_csrf_token
    begin
      response = make_request('GET', '/feed', {})
      
      if response.code == '200'
        csrf_match = response.body.match(/csrf-token["\s]*content["=\s]*([^">\s]+)/)
        token = csrf_match ? csrf_match[1] : generate_csrf_token
        Rails.logger.info "SalesNavigatorScraper: CSRF token extracted: #{token[0..10]}..."
        token
      else
        Rails.logger.warn "SalesNavigatorScraper: Failed to extract CSRF token, generating default"
        generate_csrf_token
      end
    rescue => e
      Rails.logger.error "SalesNavigatorScraper: CSRF token extraction error: #{e.message}"
      generate_csrf_token
    end
  end
  
  # Generate fallback CSRF token
  def generate_csrf_token
    "ajax:#{SecureRandom.hex(10)}"
  end
  
  # Test authentication with a simple API call
  def test_authentication
    begin
      response = make_api_request('GET', '/identity/profiles/test')
      response.present? && response.code.to_i != 401
    rescue => e
      Rails.logger.error "SalesNavigatorScraper: Authentication test error: #{e.message}"
      false
    end
  end
  
  # Search people using LinkedIn Voyager API
  def search_people_via_voyager(search_params)
    Rails.logger.info "SalesNavigatorScraper: Searching people via Voyager API"
    
    # Build the API endpoint and parameters
    endpoint = '/search/cluster'
    api_params = build_voyager_search_params(search_params)
    
    # Make the API request
    response = make_api_request('GET', endpoint, api_params)
    
    if response && response.code == '200'
      result = JSON.parse(response.body)
      profiles = parse_voyager_search_results(result)
      
      {
        success: true,
        profiles: profiles,
        total_found: profiles.size,
        source: 'voyager_api'
      }
    else
      error_msg = response ? "API request failed: #{response.code}" : "No response received"
      {
        success: false,
        error: error_msg,
        profiles: []
      }
    end
  rescue => e
    Rails.logger.error "SalesNavigatorScraper: Voyager search error: #{e.message}"
    {
      success: false,
      error: e.message,
      profiles: []
    }
  end
  
  # Build Voyager API search parameters
  def build_voyager_search_params(search_params)
    guided_filters = []
    
    # Add company filter if present
    if search_params[:company_id].present?
      guided_filters << "currentCompany->List(#{search_params[:company_id]})"
    end
    
    # Add keywords filter if present
    if search_params[:keywords].present?
      guided_filters << "keywords->#{search_params[:keywords]}"
    end
    
    # Add location filter if present
    if search_params[:location].present?
      geo_urn = convert_location_to_urn(search_params[:location])
      guided_filters << "geoUrn->#{geo_urn}" if geo_urn
    end
    
    guided_value = guided_filters.any? ? "List(#{guided_filters.join(',')})" : "List()"
    
    {
      decorationId: 'com.linkedin.voyager.search.SearchCluster',
      start: search_params[:start] || 0,
      count: search_params[:count] || 25,
      q: 'guided',
      guided: guided_value
    }
  end
  
  # Parse Voyager API search results
  def parse_voyager_search_results(api_result)
    Rails.logger.info "SalesNavigatorScraper: Parsing Voyager search results"
    
    profiles = []
    
    # Navigate the complex Voyager response structure
    data = api_result['data'] || api_result
    search_cluster = data['searchDashClustersByAll'] || data['searchCluster'] || {}
    elements = search_cluster['elements'] || []
    
    elements.each do |element|
      profile = extract_profile_from_voyager_element(element)
      profiles << profile if profile
    end
    
    Rails.logger.info "SalesNavigatorScraper: Parsed #{profiles.size} profiles from Voyager response"
    profiles
  rescue => e
    Rails.logger.error "SalesNavigatorScraper: Error parsing Voyager results: #{e.message}"
    []
  end
  
  # Extract profile data from Voyager API element
  def extract_profile_from_voyager_element(element)
    return nil unless element.is_a?(Hash)
    
    profile = {
      name: extract_profile_name(element),
      headline: element['headline'] || element['title'],
      location: element['subline'] || element['location'],
      profile_url: construct_profile_url(element),
      public_id: extract_public_id(element),
      current_company: extract_current_company(element),
      current_position: extract_current_position(element),
      connection_degree: extract_connection_degree(element),
      profile_image_url: extract_profile_image(element),
      industry: extract_industry(element),
      scraped_at: Time.current,
      source: 'voyager_api'
    }
    
    # Only return if we have essential data
    if profile[:name].present? && profile[:profile_url].present?
      Rails.logger.debug "SalesNavigatorScraper: Extracted profile: #{profile[:name]}"
      profile
    else
      Rails.logger.warn "SalesNavigatorScraper: Skipping incomplete profile data"
      nil
    end
  rescue => e
    Rails.logger.error "SalesNavigatorScraper: Error extracting profile: #{e.message}"
    nil
  end
  
  # Helper methods for profile data extraction
  def extract_profile_name(element)
    element['name'] || 
    element['title'] || 
    [element['firstName'], element['lastName']].compact.join(' ')
  end
  
  def extract_public_id(element)
    return nil unless element['entityUrn']
    
    # Extract public ID from entity URN
    urn_match = element['entityUrn'].match(/person:\(([^)]+)\)/)
    urn_match ? urn_match[1] : nil
  end
  
  def construct_profile_url(element)
    public_id = extract_public_id(element)
    public_id ? "https://www.linkedin.com/in/#{public_id}/" : nil
  end
  
  def extract_current_company(element)
    element['currentCompany'] || 
    element['company'] ||
    element.dig('currentPosition', 'companyName')
  end
  
  def extract_current_position(element)
    element['currentPosition'] || 
    element['position'] ||
    element.dig('currentPosition', 'title')
  end
  
  def extract_connection_degree(element)
    element['connectionDegree'] || 
    element['distance'] ||
    element['degree']
  end
  
  def extract_profile_image(element)
    element.dig('profilePicture', 'displayImageUrn') ||
    element.dig('image', 'attributes', 0, 'detailData', 'nonEntityProfilePicture', 'vectorImage', 'rootUrl')
  end
  
  def extract_industry(element)
    element['industry'] || element['industryName']
  end
  
  # Make API request with rate limiting and error handling
  def make_api_request(method, endpoint, params = {})
    @rate_limiter.wait_if_needed
    
    path = endpoint.start_with?('/voyager/api') ? endpoint : "/voyager/api#{endpoint}"
    
    # Add query parameters for GET requests
    if method.upcase == 'GET' && params.any?
      query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
      path += "?#{query_string}"
    end
    
    make_request(method, path, params)
  end
  
  # Make HTTP request with proper headers
  def make_request(method, path, params = {})
    return nil unless @session
    
    headers = @session_headers.dup
    headers['csrf-token'] = @csrf_token if @csrf_token
    
    # Add random delay to avoid detection
    sleep(rand(1.0..3.0))
    
    case method.upcase
    when 'GET'
      request = Net::HTTP::Get.new(path)
    when 'POST'
      request = Net::HTTP::Post.new(path)
      request.body = params.to_json
      headers['Content-Type'] = 'application/json'
    else
      raise "Unsupported HTTP method: #{method}"
    end
    
    # Set headers
    headers.each { |name, value| request[name] = value }
    
    Rails.logger.debug "SalesNavigatorScraper: #{method} #{path}"
    
    response = @session.request(request)
    Rails.logger.debug "SalesNavigatorScraper: Response: #{response.code}"
    
    handle_response(response)
  rescue => e
    Rails.logger.error "SalesNavigatorScraper: Request error: #{e.message}"
    nil
  end
  
  # Handle API response with proper error handling
  def handle_response(response)
    case response.code.to_i
    when 200
      response
    when 401
      Rails.logger.error "SalesNavigatorScraper: Authentication failed"
      @authenticated = false
      nil
    when 429
      Rails.logger.warn "SalesNavigatorScraper: Rate limited, backing off"
      sleep(60)
      nil
    when 403
      Rails.logger.error "SalesNavigatorScraper: Access forbidden"
      nil
    else
      Rails.logger.error "SalesNavigatorScraper: Request failed: #{response.code} - #{response.body[0..200]}"
      nil
    end
  end
  
  # Convert location name to LinkedIn geo URN
  def convert_location_to_urn(location_name)
    # Simplified mapping - in production, this would use LinkedIn's location API
    location_mapping = {
      'san francisco' => 'urn:li:geo:90000002',
      'new york' => 'urn:li:geo:90000003',
      'london' => 'urn:li:geo:90000004',
      'singapore' => 'urn:li:geo:90000005',
      'seattle' => 'urn:li:geo:90000006',
      'los angeles' => 'urn:li:geo:90000007'
    }
    
    location_mapping[location_name.to_s.downcase]
  end
  
  # Generate LinkedIn-compatible User-Agent
  def linkedin_user_agent
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  end
  
  # Response helper methods
  def success_response(data)
    { success: true }.merge(data)
  end
  
  def error_response(message)
    { success: false, error: message, profiles: [] }
  end
  
  # Rate limiting class
  class RateLimiter
    def initialize(max_requests_per_hour: 100)
      @max_requests = max_requests_per_hour
      @requests = []
      @mutex = Mutex.new
    end
    
    def can_make_request?
      @mutex.synchronize do
        now = Time.current
        @requests.reject! { |time| time < now - 1.hour }
        @requests.size < @max_requests
      end
    end
    
    def record_request
      @mutex.synchronize do
        @requests << Time.current
      end
    end
    
    def wait_if_needed
      unless can_make_request?
        wait_time = time_until_next_available_slot
        Rails.logger.info "SalesNavigatorScraper: Rate limit reached, waiting #{wait_time} seconds"
        sleep(wait_time)
      end
      record_request
    end
    
    private
    
    def time_until_next_available_slot
      return 0 if @requests.empty?
      
      oldest_request = @requests.min
      (oldest_request + 1.hour - Time.current).to_i.clamp(0, 3600)
    end
  end
end