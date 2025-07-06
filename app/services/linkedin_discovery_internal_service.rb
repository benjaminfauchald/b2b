# frozen_string_literal: true

# ============================================================================
# LinkedIn Discovery Internal Service
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/linkedin_discovery_internal.rb
# 
# IMPORTANT: When making changes to this service:
# 1. Check IDM status: FeatureMemories::LinkedinDiscoveryInternal.plan_status
# 2. Update implementation_log with your changes
# 3. Follow the IDM communication protocol in CLAUDE.md
# ============================================================================
#
# Internal LinkedIn Discovery service using linkedin-api Python library
# This is a more reliable alternative to browser automation scraping
class LinkedinDiscoveryInternalService < ApplicationService

  VALID_STATUSES = %w[pending processing completed failed].freeze

  def initialize
    super(service_name: "linkedin_discovery_internal")
    @service_name = "linkedin_discovery_internal"
    @service_config = ServiceConfiguration.find_by(service_name: @service_name)
  end

  def call
    return error_response("Service is not active") unless service_active?

    Rails.logger.info "Starting LinkedIn Discovery Internal service execution"

    start_time = Time.current
    processed_count = 0
    error_count = 0

    begin
      companies_to_process = find_companies_to_process
      
      if companies_to_process.empty?
        Rails.logger.info "No companies found to process"
        return success_response(processed: 0, message: "No companies to process")
      end

      Rails.logger.info "Starting processing for #{companies_to_process.count} companies"

      companies_to_process.each do |company|
        result = process_company(company)
        
        if result[:success]
          processed_count += 1
        else
          error_count += 1
          Rails.logger.error "Error processing company #{company.id}: #{result[:error]}"
        end
        
        # Update service heartbeat
        update_service_heartbeat
      end

      Rails.logger.info "Processing complete: #{processed_count} successful, #{error_count} errors in #{Time.current - start_time} seconds"
      
      success_response(
        processed: processed_count,
        errors: error_count,
        message: "Processed #{processed_count} companies with #{error_count} errors"
      )
    rescue StandardError => e
      Rails.logger.error "Service error: #{e.message}"
      error_response("Service error: #{e.message}")
    end
  end

  def process_single_company(company_id, sales_navigator_url = nil)
    company = Company.find_by(id: company_id)
    return error_response("Company not found") unless company

    # Store the Sales Navigator URL if provided
    if sales_navigator_url.present?
      company.update(linkedin_internal_sales_navigator_url: sales_navigator_url)
    end

    process_company(company)
  end

  private

  def process_company(company)
    # For the new LinkedIn API approach, we don't require a Sales Navigator URL
    # Instead, we'll search using the company name and other available data
    Rails.logger.info "Starting LinkedIn processing for company #{company.id}"

    begin
      Rails.logger.info "Initializing LinkedIn API service for company #{company.id}"
      
      # Initialize LinkedIn API service
      linkedin_service = LinkedinApiService.new
      
      Rails.logger.info "LinkedIn API service initialized successfully"

      # Prepare search parameters based on company data
      search_params = build_search_params(company)
      Rails.logger.info "Searching LinkedIn with params: #{search_params.except(:keywords)}" # Don't log sensitive search terms

      # Search for profiles using LinkedIn API
      result = linkedin_service.search_profiles(search_params)
      
      if result[:success]
        profiles = result[:profiles]
        Rails.logger.info "Found #{profiles.length} profiles successfully"

        # Save profiles to Person model
        saved_count = save_profiles(company, profiles)

        # Update company status
        company.update!(
          linkedin_internal_processed: true,
          linkedin_internal_last_processed_at: Time.current,
          linkedin_internal_profile_count: saved_count,
          linkedin_internal_error_message: nil
        )

        Rails.logger.info "Successfully completed LinkedIn processing for company #{company.id}"
        Rails.logger.info "Processed company #{company.id} - found #{saved_count} profiles"

        { success: true, profiles_count: saved_count }
      else
        error_msg = "LinkedIn API search failed: #{result[:error]}"
        company.update(
          linkedin_internal_error_message: error_msg,
          linkedin_internal_last_processed_at: Time.current
        )
        
        Rails.logger.error "Failed LinkedIn processing for company #{company.id}: #{error_msg}"
        { success: false, error: error_msg }
      end
    rescue StandardError => e
      company.update(
        linkedin_internal_error_message: e.message,
        linkedin_internal_last_processed_at: Time.current
      )
      
      Rails.logger.error "Failed LinkedIn processing for company #{company.id}: #{e.message}"
      Rails.logger.error "Error processing company #{company.id}: #{e.message}"

      { success: false, error: e.message }
    end
  end

  def build_search_params(company)
    # Build search parameters based on company data
    search_params = {
      limit: setting("max_profiles_per_company", 56) # Increase to match expected results
    }
    
    # If we have a Sales Navigator URL from the form, try to extract search terms
    if company.linkedin_internal_sales_navigator_url.present?
      extracted_params = extract_search_params_from_url(company.linkedin_internal_sales_navigator_url)
      
      # Only use company from URL, skip keywords
      if extracted_params[:company].present?
        search_params[:company] = extracted_params[:company]
      end
      
      # Don't add keywords from URL extraction
      # search_params.merge!(extracted_params) # Removed this line
    else
      # Fall back to company name if no Sales Navigator URL
      company_name = company.try(:company_name) || company.try(:name)
      if company_name.present?
        search_params[:company] = company_name
      end
    end
    
    # Add location if available from company data
    location = company.try(:business_city) || company.try(:postal_city) || company.try(:business_address) || company.try(:postal_address)
    if location.present?
      search_params[:location] = location
    end
    
    search_params
  end
  
  def extract_search_params_from_url(sales_navigator_url)
    # Try to extract search parameters from Sales Navigator URL
    # This is a best-effort attempt to parse the complex Sales Navigator query format
    extracted_params = {}
    
    begin
      uri = URI.parse(sales_navigator_url)
      query_params = URI.decode_www_form(uri.query || "").to_h
      
      # Look for common Sales Navigator parameters
      if query_params["query"].present?
        query_data = query_params["query"]
        Rails.logger.info "Sales Navigator query data: #{query_data}"
        
        # Try to extract keywords from the URL
        if query_data.include?("keywords")
          # Look for keywords parameter - Sales Navigator format is keywords:value
          keywords_match = query_data.match(/keywords[^:]*:([^)]+)/)
          if keywords_match
            # Clean up the keywords value
            keywords = keywords_match[1].gsub("%20", " ").gsub("%2520", " ")
            extracted_params[:keywords] = keywords
            Rails.logger.info "Extracted keywords from URL: #{keywords}"
          end
        end
        
        # Try to extract company information from filters
        if query_data.include?("CURRENT_COMPANY") && query_data.include?("text:")
          # Look for company text in the filters - format is text:CompanyName
          company_match = query_data.match(/text:([^,)]+)/)
          if company_match
            company_name = company_match[1].gsub("%20", " ").gsub("%2520", " ")
            extracted_params[:company] = company_name
            Rails.logger.info "Extracted company from URL: #{company_name}"
          end
        end
      end
      
      Rails.logger.info "Final extracted search params from URL: #{extracted_params}"
    rescue => e
      Rails.logger.warn "Failed to parse Sales Navigator URL: #{e.message}"
    end
    
    extracted_params
  end

  def save_profiles(company, profiles)
    saved_count = 0

    profiles.each do |profile_data|
      person = Person.find_or_initialize_by(
        profile_url: profile_data[:profile_url],
        company_id: company.id
      )

      person.assign_attributes(
        name: profile_data[:name],
        title: profile_data[:headline] || profile_data[:current_position], # linkedin-api uses 'headline'
        location: profile_data[:location],
        connection_degree: profile_data[:connection_degree],
        linkedin_data: profile_data,
        profile_extracted_at: Time.current,
        source: "linkedin_internal"
      )

      if person.save
        saved_count += 1
        Rails.logger.info "Saved profile: #{person.name} (ID: #{person.id})"
      else
        Rails.logger.warn "Failed to save profile: #{person.errors.full_messages.join(', ')}"
      end
    end

    saved_count
  end

  def find_companies_to_process
    # Find companies that haven't been processed yet or need refresh
    base_scope = Company
      .where(company_name: [nil, ""].not) # Only process companies with names
      .order(:linkedin_internal_last_processed_at)
      .limit(batch_size)

    # Apply refresh interval
    if refresh_interval_hours.positive?
      cutoff_date = refresh_interval_hours.hours.ago
      base_scope = base_scope.where(
        "linkedin_internal_last_processed_at IS NULL OR linkedin_internal_last_processed_at < ?",
        cutoff_date
      )
    end

    base_scope
  end

  def service_active?
    @service_config&.active?
  end

  def batch_size
    @service_config&.batch_size || 10
  end

  def refresh_interval_hours
    @service_config&.refresh_interval_hours || 2160 # 90 days default
  end

  def setting(key, default = nil)
    @service_config&.settings&.dig(key) || default
  end

  def update_service_heartbeat
    @service_config&.touch(:last_run_at) if @service_config
  end

  def success_response(data)
    { success: true }.merge(data)
  end

  def error_response(message)
    { success: false, error: message }
  end
end