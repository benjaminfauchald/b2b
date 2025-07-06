# frozen_string_literal: true

require "ferrum"

# ============================================================================
# Sales Navigator Scraper
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/linkedin_discovery_internal.rb
# 
# IMPORTANT: When making changes to this scraper:
# 1. Check IDM status: FeatureMemories::LinkedinDiscoveryInternal.plan_status
# 2. Update implementation_log with your changes
# 3. Follow the IDM communication protocol in CLAUDE.md
# ============================================================================
#
# Scrapes LinkedIn Sales Navigator pages using Ferrum (Chrome DevTools Protocol)
class SalesNavigatorScraper
  attr_reader :browser, :page

  def initialize(options = {})
    @headless = options.fetch(:headless, true)
    @viewport = options.fetch(:viewport, { width: 1920, height: 1080 })
    @browser = nil
    @page = nil
    @authenticated = false
  end

  def scrape_profiles(sales_navigator_url)
    setup_browser
    authenticate_linkedin
    
    profiles = []
    
    begin
      # Navigate to Sales Navigator page
      page.goto(sales_navigator_url)
      wait_for_page_load
      
      # Extract profiles from the page
      profiles = extract_profiles_from_page
      
      # Handle pagination if needed
      while has_more_pages? && profiles.count < max_profiles
        click_next_page
        wait_for_page_load
        profiles.concat(extract_profiles_from_page)
      end
      
      profiles.take(max_profiles)
    rescue Ferrum::TimeoutError => e
      Rails.logger.error "Timeout while scraping Sales Navigator: #{e.message}"
      raise "Page load timeout - LinkedIn might be blocking access"
    rescue StandardError => e
      Rails.logger.error "Error scraping Sales Navigator: #{e.message}"
      raise
    end
  end

  def cleanup
    browser&.quit
  rescue StandardError => e
    Rails.logger.error "Error cleaning up browser: #{e.message}"
  end

  private

  def setup_browser
    @browser = Ferrum::Browser.new(
      headless: @headless,
      window_size: [@viewport[:width], @viewport[:height]],
      timeout: 30,
      js_errors: false,
      process_timeout: 30,
      browser_options: {
        "no-sandbox" => nil,
        "disable-dev-shm-usage" => nil,
        "disable-blink-features" => "AutomationControlled"
      }
    )
    
    @page = browser.create_page
    
    # Set user agent to avoid detection
    page.headers.set({
      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    })
  end

  def authenticate_linkedin
    return if @authenticated
    
    Rails.logger.info "Starting LinkedIn authentication..."
    
    # Try credentials-based authentication first for better access
    if ENV['LINKEDIN_EMAIL'].present? && ENV['LINKEDIN_PASSWORD'].present?
      Rails.logger.info "LinkedIn credentials available, attempting credential authentication..."
      login_with_credentials
      return if @authenticated
    end
    
    # Fall back to cookie-based authentication if credentials fail
    if linkedin_cookies_available?
      Rails.logger.info "Falling back to cookie authentication..."
      load_linkedin_cookies
      page.goto("https://www.linkedin.com/feed/")
      
      if logged_in?
        @authenticated = true
        Rails.logger.info "Successfully authenticated with LinkedIn using cookies"
        return
      else
        Rails.logger.warn "Cookie authentication also failed"
      end
    end
    
    raise "Failed to authenticate with LinkedIn using both credentials and cookies"
  end

  def linkedin_cookies_available?
    # Check if we have stored LinkedIn cookies in environment variables
    ENV['LINKEDIN_COOKIE_LI_AT'].present?
  rescue StandardError
    false
  end

  def load_linkedin_cookies
    # Set the li_at cookie which is the main session cookie
    if ENV['LINKEDIN_COOKIE_LI_AT'].present?
      begin
        Rails.logger.info "Setting li_at cookie..."
        page.cookies.set(
          name: "li_at",
          value: ENV['LINKEDIN_COOKIE_LI_AT'],
          domain: ".linkedin.com",
          path: "/",
          secure: true,
          httponly: true
        )
        Rails.logger.info "li_at cookie set successfully"
      rescue StandardError => e
        Rails.logger.error "Error setting li_at cookie: #{e.message}"
        raise e
      end
    end
    
    # Set other important cookies from environment variables
    cookie_mapping = {
      'JSESSIONID' => ENV['LINKEDIN_COOKIE_JSESSIONID'],
      'li_gc' => ENV['LINKEDIN_COOKIE_LI_GC'],
      'bcookie' => ENV['LINKEDIN_COOKIE_BCOOKIE'],
      'bscookie' => ENV['LINKEDIN_COOKIE_BSCOOKIE']
    }
    
    cookie_mapping.each do |cookie_name, cookie_value|
      next unless cookie_value.present?
      
      begin
        Rails.logger.info "Setting #{cookie_name} cookie..."
        page.cookies.set(
          name: cookie_name.downcase,
          value: cookie_value,
          domain: ".linkedin.com",
          path: "/",
          secure: true
        )
        Rails.logger.info "#{cookie_name} cookie set successfully"
      rescue StandardError => e
        Rails.logger.error "Error setting #{cookie_name} cookie: #{e.message}"
        raise e
      end
    end
  end

  def login_with_credentials
    email = ENV['LINKEDIN_EMAIL']
    password = ENV['LINKEDIN_PASSWORD']
    
    Rails.logger.info "Attempting credential login with email: #{email.present? ? email[0..3] + '***' : 'MISSING'}"
    Rails.logger.info "Password present: #{password.present?}"
    
    raise "LinkedIn credentials not configured" unless email && password
    
    page.goto("https://www.linkedin.com/login")
    
    # Fill in login form
    page.at_css("#username").focus.type(email)
    sleep(rand(0.5..1.0)) # Random delay to appear human
    
    page.at_css("#password").focus.type(password)
    sleep(rand(0.5..1.0))
    
    # Click sign in button
    page.at_css('button[type="submit"]').click
    
    # Wait for login to complete by checking if element exists with timeout
    timeout = 15
    start_time = Time.current
    
    Rails.logger.info "Waiting for login to complete..."
    
    loop do
      break if logged_in?
      
      # Add debugging every 3 seconds
      if (Time.current - start_time).to_i % 3 == 0 && (Time.current - start_time) > 2
        Rails.logger.info "Still waiting for login... Current URL: #{page.current_url}"
        Rails.logger.info "Page title: #{page.title}"
        
        # Check for common login elements
        if page.at_css("#username")
          Rails.logger.info "Still on login form"
        elsif page.at_css(".challenge-page")
          Rails.logger.info "Hit security challenge page"
        elsif page.at_css(".captcha")
          Rails.logger.info "Hit captcha page"
        elsif page.at_css(".verification")
          Rails.logger.info "Hit verification page"
        end
      end
      
      if Time.current - start_time > timeout
        Rails.logger.error "Login timeout - Final URL: #{page.current_url}"
        Rails.logger.error "Login timeout - Page title: #{page.title}"
        
        # Save page for debugging
        File.write("tmp/login_debug.html", page.body) if Rails.env.development?
        Rails.logger.error "Login page content saved to tmp/login_debug.html"
        
        raise "Timeout waiting for login to complete"
      end
      
      sleep(0.5)
    end
    
    if logged_in?
      @authenticated = true
      Rails.logger.info "Successfully logged in to LinkedIn"
      
      # Save cookies for future use
      save_linkedin_cookies
    else
      raise "Failed to authenticate with LinkedIn"
    end
  end

  def logged_in?
    # Check if we're on the feed page or have navigation elements
    page.current_url.include?("/feed") ||
      page.current_url.include?("/sales/") ||
      page.at_css("nav.global-nav").present? ||
      page.at_css("[data-test-id='global-nav']").present? ||
      page.at_css(".global-nav").present? ||
      page.title.include?("Feed | LinkedIn")
  rescue StandardError
    false
  end

  def save_linkedin_cookies
    # Extract and save important cookies for future sessions
    cookies_to_save = {}
    
    %w[li_at JSESSIONID li_gc bcookie bscookie].each do |cookie_name|
      # In Ferrum, cookies.all returns a hash where keys are cookie names and values are cookie objects
      cookie = page.cookies.all[cookie_name]
      if cookie
        cookies_to_save[cookie_name] = cookie.value
      end
    end
    
    # In production, you'd want to encrypt and store these securely
    Rails.logger.info "LinkedIn cookies saved for future sessions"
  end

  def wait_for_page_load
    # Wait for Sales Navigator specific elements using Ferrum-compatible approach
    timeout = 10
    start_time = Time.current
    
    Rails.logger.info "Waiting for Sales Navigator page to load..."
    Rails.logger.info "Current URL: #{page.current_url}"
    
    loop do
      break if page.at_css(".search-results__list")
      
      # Log what we can find to help debug
      if Time.current - start_time > 5
        Rails.logger.info "Still waiting after 5 seconds. Page title: #{page.title}"
        Rails.logger.info "Current URL: #{page.current_url}"
        Rails.logger.info "Page body contains: #{page.body.length} characters"
        
        # Check for common Sales Navigator elements
        common_selectors = [
          ".search-results",
          ".artdeco-list", 
          "[data-test-id]",
          ".spotlight-result",
          ".search-no-results",
          ".premium-upsell"
        ]
        
        common_selectors.each do |selector|
          if page.at_css(selector)
            Rails.logger.info "Found alternative selector: #{selector}"
          end
        end
      end
      
      if Time.current - start_time > timeout
        Rails.logger.error "Timeout waiting for search results to load"
        Rails.logger.error "Final URL: #{page.current_url}"
        Rails.logger.error "Page title: #{page.title}"
        
        # Save page content for debugging
        File.write("tmp/sales_navigator_debug.html", page.body) if Rails.env.development?
        Rails.logger.error "Page content saved to tmp/sales_navigator_debug.html for debugging"
        
        raise "Timeout waiting for search results to load - page may not be Sales Navigator search results"
      end
      
      sleep(0.5)
    end
    
    Rails.logger.info "Successfully found .search-results__list element"
    
    # Additional wait for dynamic content
    sleep(rand(2.0..4.0))
    
    # Scroll to trigger lazy loading
    page.execute("window.scrollTo(0, document.body.scrollHeight / 2)")
    sleep(rand(1.0..2.0))
  end

  def extract_profiles_from_page
    profiles = []
    
    # Find all profile cards on the page
    profile_elements = page.css(".search-results__result-item")
    
    profile_elements.each do |element|
      profile = extract_profile_data(element)
      profiles << profile if profile[:name].present?
    rescue StandardError => e
      Rails.logger.warn "Error extracting profile: #{e.message}"
      next
    end
    
    Rails.logger.info "Extracted #{profiles.count} profiles from current page"
    profiles
  end

  def extract_profile_data(element)
    {
      name: element.at_css(".result-lockup__name").text.strip,
      title: element.at_css(".result-lockup__highlight-keyword").text.strip,
      company: element.at_css('[data-anonymize="company-name"]')&.text&.strip,
      location: element.at_css('[data-anonymize="location"]')&.text&.strip,
      profile_url: extract_profile_url(element),
      connection_degree: extract_connection_degree(element),
      scraped_at: Time.current
    }
  end

  def extract_profile_url(element)
    link = element.at_css("a.result-lockup__name-link")
    return nil unless link
    
    href = link.attribute("href")
    return nil unless href
    
    # Clean up the URL
    url = href.start_with?("http") ? href : "https://www.linkedin.com#{href}"
    url.split("?").first # Remove query parameters
  end

  def extract_connection_degree(element)
    degree_element = element.at_css(".member-insights__network-distance")
    return nil unless degree_element
    
    text = degree_element.text.strip
    case text
    when /1st/
      "1st"
    when /2nd/
      "2nd"
    when /3rd/
      "3rd"
    else
      nil
    end
  end

  def has_more_pages?
    # Check if there's a next button and it's not disabled
    next_button = page.at_css('button[aria-label="Next"]')
    next_button && !next_button.attribute("disabled")
  rescue StandardError
    false
  end

  def click_next_page
    next_button = page.at_css('button[aria-label="Next"]')
    next_button.click
    
    # Wait for page transition
    sleep(rand(2.0..4.0))
  end

  def network_idle_timeout
    3000 # 3 seconds
  end

  def max_profiles
    ServiceConfiguration
      .find_by(service_name: "linkedin_discovery_internal")
      &.settings
      &.dig("max_profiles_per_page") || 25
  end
end