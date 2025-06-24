require 'ostruct'
require 'net/http'
require 'json'
require 'uri'

class CompanyLinkedinDiscoveryService < ApplicationService
  def initialize(company)
    @company = company
    super(service_name: 'company_linkedin_discovery', action: 'process')
  end

  def perform
    return error_result('Service is disabled') unless service_active?
    
    audit_service_operation(@company) do |audit_log|
      unless needs_update?
        audit_log.update!(
          status: :success,
          metadata: audit_log.metadata.merge(reason: 'up_to_date', skipped: true),
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
        )
        # Early return to avoid API call
        next success_result('LinkedIn data is up to date')
      end
      
      # Search for LinkedIn profile
      response = search_linkedin_profile
      Rails.logger.debug "LinkedIn Search Response: #{response.inspect}" if Rails.env.test?
      
      if response[:success]
        # Validate the LinkedIn data
        unless valid_linkedin_data?(response[:data])
          raise StandardError.new('Invalid LinkedIn data structure')
        end
        
        update_company_linkedin(response[:data])
        
        # Add metadata for successful API response
        audit_log.add_metadata(
          api_response_code: 200,
          linkedin_found: response[:data][:linkedin_url].present?
        )
        
        success_result('LinkedIn profile discovered', linkedin_data: response[:data])
      elsif response[:rate_limited]
        # Create a custom exception that includes the retry_after info
        error = StandardError.new('API rate limit exceeded')
        error.define_singleton_method(:retry_after) { response[:retry_after] }
        raise error
      else
        raise StandardError.new(response[:error] || 'Failed to search LinkedIn profile')
      end
    end
  rescue StandardError => e
    # For rate limit errors, include retry_after in the result data
    if e.message.include?('rate limit') && e.respond_to?(:retry_after)
      error_result(e.message, retry_after: e.retry_after)
    else
      error_result("Service error: #{e.message}")
    end
  end
  
  private
  
  def service_active?
    config = ServiceConfiguration.find_by(service_name: 'company_linkedin_discovery')
    config&.active?
  end
  
  def needs_update?
    # Use the ServiceAuditable concern's needs_service? method which checks audit logs
    @company.needs_service?('company_linkedin_discovery')
  end
  
  def search_linkedin_profile
    # This would be a real LinkedIn search API in production
    api_endpoint = ENV['LINKEDIN_SEARCH_API_ENDPOINT'] || 'https://api.linkedin.example.com'
    company_name = @company.company_name
    
    begin
      uri = URI("#{api_endpoint}/search?company=#{URI.encode_www_form_component(company_name)}")
      Rails.logger.debug "Searching LinkedIn at: #{uri}" if Rails.env.test?
      response = Net::HTTP.get_response(uri)
      
      case response.code.to_i
      when 200
        data = JSON.parse(response.body, symbolize_names: true)
        { success: true, data: data }
      when 429
        retry_after = response['Retry-After']&.to_i || 3600
        { success: false, rate_limited: true, retry_after: retry_after }
      else
        { success: false, error: "API error: #{response.code} - #{response.message}" }
      end
    rescue StandardError => e
      { success: false, error: "Request failed: #{e.message}" }
    end
  end
  
  def valid_linkedin_data?(data)
    data.is_a?(Hash) && (data.key?(:linkedin_url) || data.key?(:not_found))
  end
  
  def update_company_linkedin(data)
    updates = {
      linkedin_processed: true,
      linkedin_last_processed_at: Time.current
    }
    
    if data[:linkedin_url]
      updates[:linkedin_url] = data[:linkedin_url]
      updates[:linkedin_ai_confidence] = data[:confidence]
    end
    
    @company.update!(updates)
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