require 'ostruct'

class CompanyFinancialDataService < ApplicationService
  def initialize(company)
    @company = company
    super(service_name: 'company_financial_data', action: 'process')
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
        next success_result('Financial data is up to date')
      end
      
      # Fetch financial data from external API
      response = fetch_financial_data
      Rails.logger.debug "API Response: #{response.inspect}" if Rails.env.test?
      
      if response[:success]
        # Validate the financial data structure
        unless valid_financial_data?(response[:data])
          raise StandardError.new('Invalid financial data structure')
        end
        
        update_company_financials(response[:data])
        
        # Add metadata for successful API response
        audit_log.add_metadata(
          api_response_code: 200,
          financial_data: response[:data]
        )
        
        success_result('Financial data updated', financial_data: response[:data])
      elsif response[:rate_limited]
        # Create a custom exception that includes the retry_after info
        error = StandardError.new('API rate limit exceeded')
        error.define_singleton_method(:retry_after) { response[:retry_after] }
        raise error
      else
        raise StandardError.new(response[:error] || 'Failed to fetch financial data')
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
    config = ServiceConfiguration.find_by(service_name: 'company_financial_data')
    config&.active?
  end
  
  def needs_update?
    # Use the ServiceAuditable concern's needs_service? method which checks audit logs
    @company.needs_service?('company_financial_data')
  end
  
  def fetch_financial_data
    require 'net/http'
    require 'json'
    
    # Use the same endpoint as defined in the test
    api_endpoint = ENV['BRREG_API_ENDPOINT'] || 'https://api.brreg.no'
    registration_number = @company.registration_number
    
    begin
      uri = URI("#{api_endpoint}/regnskapsregisteret/regnskap/#{registration_number}")
      Rails.logger.debug "Fetching financial data from: #{uri}" if Rails.env.test?
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
  
  def valid_financial_data?(data)
    required_fields = [:revenue, :profit, :equity, :total_assets, :current_assets, 
                      :fixed_assets, :current_liabilities, :long_term_liabilities, :year]
    
    data.is_a?(Hash) && required_fields.all? { |field| data.key?(field) }
  end
  
  def update_company_financials(data)
    @company.update!(
      revenue: data[:revenue],
      profit: data[:profit],
      equity: data[:equity],
      total_assets: data[:total_assets],
      current_assets: data[:current_assets],
      fixed_assets: data[:fixed_assets],
      current_liabilities: data[:current_liabilities],
      long_term_liabilities: data[:long_term_liabilities],
      year: data[:year],
      financial_data_updated_at: Time.current
    )
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