# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'selenium-webdriver'

# Service to convert LinkedIn company URLs to Sales Navigator URLs
# This service extracts the organization ID from LinkedIn company pages
# and constructs the corresponding Sales Navigator search URL
class LinkedinSalesNavigatorConverter
  SALES_NAV_BASE_URL = 'https://www.linkedin.com/sales/search/people'
  
  # LinkedIn company URL patterns
  COMPANY_URL_PATTERN = %r{linkedin\.com/company/([^/]+)/?}
  ORGANIZATION_URN_PATTERN = /urn:li:organization:(\d+)/
  ORGANIZATION_URN_ENCODED_PATTERN = /urn%3Ali%3Aorganization%3A(\d+)/
  
  attr_reader :errors

  def initialize
    @errors = []
  end

  # Main method to convert LinkedIn company URL to Sales Navigator URL
  # @param company_url [String] LinkedIn company page URL
  # @return [Hash] Result with sales_navigator_url and metadata
  def convert(company_url)
    @errors.clear
    
    # Extract company slug from URL
    company_slug = extract_company_slug(company_url)
    unless company_slug
      @errors << "Invalid LinkedIn company URL format"
      return { success: false, errors: @errors }
    end

    # Extract organization ID and company name
    company_data = extract_company_data(company_url)
    unless company_data[:success]
      return company_data
    end

    # Build Sales Navigator URL
    sales_nav_url = build_sales_navigator_url(
      company_data[:organization_id],
      company_data[:company_name]
    )

    {
      success: true,
      company_url: company_url,
      company_slug: company_slug,
      organization_id: company_data[:organization_id],
      company_name: company_data[:company_name],
      sales_navigator_url: sales_nav_url
    }
  end

  # Batch convert multiple LinkedIn company URLs
  # @param company_urls [Array<String>] Array of LinkedIn company URLs
  # @return [Array<Hash>] Array of conversion results
  def batch_convert(company_urls)
    company_urls.map { |url| convert(url) }
  end

  private

  # Extract company slug from LinkedIn URL
  def extract_company_slug(url)
    match = url.match(COMPANY_URL_PATTERN)
    match ? match[1] : nil
  end

  # Extract company data (organization ID and name) from LinkedIn page
  # This method tries multiple approaches:
  # 1. JavaScript extraction using Selenium (most reliable)
  # 2. HTTP request with regex parsing (faster but less reliable)
  def extract_company_data(company_url)
    # Try JavaScript extraction first (requires Selenium)
    if selenium_available?
      result = extract_with_selenium(company_url)
      return result if result[:success]
    end

    # Fallback to HTTP extraction
    extract_with_http(company_url)
  end

  # Check if Selenium WebDriver is available
  def selenium_available?
    defined?(Selenium::WebDriver)
  rescue StandardError
    false
  end

  # Extract company data using Selenium WebDriver
  def extract_with_selenium(company_url)
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    
    driver = Selenium::WebDriver.for :chrome, options: options

    begin
      driver.navigate.to company_url
      
      # Wait for page to load
      wait = Selenium::WebDriver::Wait.new(timeout: 10)
      wait.until { driver.find_element(tag_name: 'body') }

      # Execute JavaScript to extract organization data
      organization_data = driver.execute_script(<<-JS)
        function extractLinkedInData() {
          const codeElements = document.querySelectorAll('code');
          let companyData = { organizationId: null, companyName: null };
          
          // Try to find company name from page
          const h1 = document.querySelector('h1');
          if (h1) {
            companyData.companyName = h1.textContent.trim();
          }
          
          // Search for organization URN in JSON data
          for (let element of codeElements) {
            try {
              const data = JSON.parse(element.textContent);
              
              const searchData = (obj) => {
                for (let key in obj) {
                  if (typeof obj[key] === 'string') {
                    // Check for organization URN
                    const match = obj[key].match(/urn:li:organization:(\\d+)/);
                    if (match) {
                      companyData.organizationId = match[1];
                      // Also try to get company name from the data
                      if (obj.name) companyData.companyName = obj.name;
                      if (obj.universalName) companyData.companyName = obj.universalName;
                    }
                  } else if (typeof obj[key] === 'object' && obj[key] !== null) {
                    searchData(obj[key]);
                  }
                }
              };
              
              searchData(data);
              if (companyData.organizationId) break;
            } catch (e) {
              // Skip invalid JSON
            }
          }
          
          // Alternative: Search in page source
          if (!companyData.organizationId) {
            const pageSource = document.documentElement.innerHTML;
            const matches = pageSource.match(/urn:li:organization:(\\d+)/);
            if (matches) {
              companyData.organizationId = matches[1];
            }
          }
          
          return companyData;
        }
        
        return extractLinkedInData();
      JS

      if organization_data && organization_data['organizationId']
        {
          success: true,
          organization_id: organization_data['organizationId'],
          company_name: organization_data['companyName'] || extract_company_name_from_url(company_url)
        }
      else
        @errors << "Could not extract organization ID from page"
        { success: false, errors: @errors }
      end
    rescue StandardError => e
      @errors << "Selenium extraction failed: #{e.message}"
      { success: false, errors: @errors }
    ensure
      driver&.quit
    end
  end

  # Extract company data using HTTP request (fallback method)
  def extract_with_http(company_url)
    uri = URI(company_url)
    
    # Set up HTTP request with headers to mimic browser
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    request['Accept-Language'] = 'en-US,en;q=0.5'
    
    response = http.request(request)
    
    if response.code == '200'
      body = response.body
      
      # Try to extract organization ID
      organization_id = nil
      
      # Try different patterns
      [ORGANIZATION_URN_PATTERN, ORGANIZATION_URN_ENCODED_PATTERN].each do |pattern|
        match = body.match(pattern)
        if match
          organization_id = match[1]
          break
        end
      end
      
      if organization_id
        # Try to extract company name
        company_name = extract_company_name_from_html(body) || extract_company_name_from_url(company_url)
        
        {
          success: true,
          organization_id: organization_id,
          company_name: company_name
        }
      else
        @errors << "Could not find organization ID in page source"
        { success: false, errors: @errors }
      end
    else
      @errors << "HTTP request failed with status #{response.code}"
      { success: false, errors: @errors }
    end
  rescue StandardError => e
    @errors << "HTTP extraction failed: #{e.message}"
    { success: false, errors: @errors }
  end

  # Extract company name from HTML
  def extract_company_name_from_html(html)
    # Try to find company name in title tag
    title_match = html.match(/<title>([^|]+)/)
    return title_match[1].strip if title_match
    
    # Try to find in h1 tag
    h1_match = html.match(/<h1[^>]*>([^<]+)/)
    return h1_match[1].strip if h1_match
    
    nil
  end

  # Extract company name from URL (fallback)
  def extract_company_name_from_url(url)
    slug = extract_company_slug(url)
    return nil unless slug
    
    # Convert slug to company name (replace hyphens with spaces and capitalize)
    slug.split('-').map(&:capitalize).join(' ')
  end

  # Build Sales Navigator URL from organization ID and company name
  def build_sales_navigator_url(organization_id, company_name)
    # URL encode the company name twice (LinkedIn uses double encoding)
    encoded_name = URI.encode_www_form_component(company_name)
    double_encoded_name = URI.encode_www_form_component(encoded_name)
    
    # Build the query parameters (without keywords parameter)
    query_params = {
      query: "(spellCorrectionEnabled:true,recentSearchParam:(id:#{rand(1000000000..9999999999)},doLogHistory:true),filters:List((type:CURRENT_COMPANY,values:List((id:urn%3Ali%3Aorganization%3A#{organization_id},text:#{double_encoded_name},selectionType:INCLUDED,parent:(id:0))))))",
      sessionId: generate_session_id
    }
    
    # Build the full URL
    uri = URI(SALES_NAV_BASE_URL)
    uri.query = URI.encode_www_form(query_params)
    uri.to_s
  end

  # Generate a random session ID similar to LinkedIn's format
  def generate_session_id
    # LinkedIn session IDs appear to be base64-like strings
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['+', '/', '=']
    (0...24).map { chars.sample }.join + '=='
  end
end

# Example usage:
# converter = LinkedinSalesNavigatorConverter.new
# result = converter.convert('https://www.linkedin.com/company/crowe-norway/')
# puts result[:sales_navigator_url] if result[:success]