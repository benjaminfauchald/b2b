require "ostruct"

class CompanyFinancialsService < ApplicationService
  include HttpartyResponseHelper

  BASE_URL = "https://data.brreg.no/regnskapsregisteret/regnskap".freeze
  MAX_ATTEMPTS = 3
  INITIAL_RETRY_DELAY = 2 # seconds

  class ApiError < StandardError; end
  class RateLimitError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after = nil)
      super(message)
      @retry_after = retry_after
    end
  end
  class InvalidResponseError < StandardError; end

  def initialize(company:, **options)
    @company = company
    @org_number = company.registration_number
    @attempts = 0
    super(service_name: "company_financials", action: "update", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("No organization number") unless @org_number.present?

    # Check if update is needed before starting audit
    unless needs_update?
      return success_result("Financial data is up to date")
    end

    audit_service_operation(@company) do |audit_log|
      Rails.logger.info "🚀 Starting financial data update for #{@company.company_name} (#{@org_number})"
      
      result = fetch_and_update_financials
      
      if result[:success]
        audit_log.add_metadata(
          changed_fields: result[:changed_fields],
          financials: result[:financials],
          organization_number: @org_number
        )
        
        success_result("Financial data updated successfully", 
                      changed_fields: result[:changed_fields],
                      financials: result[:financials])
      else
        error_result("Failed to update financial data")
      end
    end
  rescue RateLimitError => e
    # For rate limit errors, include retry_after in the result data
    if e.message.include?("rate limit") && e.respond_to?(:retry_after)
      error_result(e.message, retry_after: e.retry_after)
    else
      error_result("Service error: #{e.message}")
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "company_financials")
    return false unless config
    config.active?
  end

  def needs_update?
    @company.needs_service?("company_financials")
  end

  def fetch_and_update_financials
    @attempts ||= 0

    begin
      financial_data = make_api_request

      # If we got financial data, process it
      if financial_data.present?
        Rails.logger.info "✅ Successfully fetched financial data for #{@org_number}"
        process_financial_data(financial_data)
      else
        Rails.logger.warn "⚠️ No financial data available for #{@org_number}"
        { success: true, changed_fields: [], financials: {} }
      end

    rescue RateLimitError => e
      Rails.logger.warn "⏰ Rate limited. Waiting #{e.retry_after} seconds..."
      sleep(e.retry_after)
      retry
    rescue ApiError, InvalidResponseError => e
      Rails.logger.error "❌ Error fetching financial data: #{e.message}"
      @attempts += 1

      if @attempts < MAX_ATTEMPTS
        retry_delay = INITIAL_RETRY_DELAY * (2 ** (@attempts - 1))
        Rails.logger.info "🔄 Retrying in #{retry_delay} seconds... (Attempt #{@attempts + 1}/#{MAX_ATTEMPTS})"
        sleep(retry_delay)
        retry
      else
        Rails.logger.error "❌ Max retries reached for #{@org_number}"
        raise
      end
    end
  end

  def process_financial_data(api_result)
    # api_result now contains both parsed_data and raw_response
    if api_result.is_a?(Hash) && api_result.key?(:parsed_data)
      financials = api_result[:parsed_data]
      raw_response = api_result[:raw_response]
    else
      # Fallback for backward compatibility
      financials = api_result
      raw_response = nil
    end

    if financials.any?
      changed_fields = update_company_financials(financials, raw_response)
      publish_to_kafka(financials)

      {
        success: true,
        changed_fields: changed_fields,
        financials: financials
      }
    else
      Rails.logger.info "ℹ️ No financial data to process for #{@org_number}"
      { success: true, changed_fields: [], financials: {} }
    end
  end

  def make_api_request
    # Enforce global rate limiting before making the API call
    enforce_rate_limit!

    # Construct the full URL with the organization number
    url = "#{BASE_URL}/#{@org_number}"

    Rails.logger.info "📡 Fetching financial data for #{@org_number} - Attempt #{@attempts}/#{MAX_ATTEMPTS}"
    Rails.logger.debug "🔗 Request URL: #{url}"

    begin
      # Add headers for the BRREG API
      headers = {
        "Accept" => "application/json",
        "User-Agent" => "B2B-Services/1.0",
        "Accept-Encoding" => "gzip, deflate, br"
      }

      Rails.logger.debug "📋 Request headers: #{headers.inspect}"

      # Make the request with a reasonable timeout
      response = handle_httparty_request(url, {
        headers: headers,
        timeout: 30,
        verify: true
      })

      # Check if response is nil (returned by handle_httparty_request for invalid responses)
      if response.nil?
        Rails.logger.warn "⚠️ No valid response received for #{@org_number} (likely 404 or network error)"
        return nil
      end

      # Explicitly check response body for nil or empty (HTTParty deprecation fix)
      if response.body.nil? || response.body.empty?
        Rails.logger.warn "⚠️ No valid response body received for #{@org_number}"
        return nil
      end

      Rails.logger.debug "📊 Response code: #{response.code}"
      Rails.logger.debug "📋 Response headers: #{response.headers.inspect}"

      # Check for rate limiting
      if response.code == 429
        retry_after = response.headers["Retry-After"]&.to_i || 60
        Rails.logger.warn "⏰ Rate limited. Waiting #{retry_after} seconds..."
        raise RateLimitError.new("Rate limited", retry_after)
      end

      # Check if we have a successful response
      if response.success?
        # Parse the JSON response
        begin
          parsed_body = JSON.parse(response.body)
        rescue JSON::ParserError => e
          Rails.logger.error "❌ Failed to parse response for #{@org_number}: #{e.message}"
          raise InvalidResponseError, "Invalid JSON response"
        end

        Rails.logger.debug "📄 Parsed response: #{parsed_body.inspect}"

        # Parse the financial data from the response
        parsed_response = parse_response(parsed_body)

        if parsed_response.nil? || parsed_response.empty?
          Rails.logger.info "ℹ️ No financial data found for #{@org_number}"
          return nil
        end

        # Return both parsed data and raw response
        { parsed_data: parsed_response, raw_response: response.body }
      else
        Rails.logger.error "❌ API request failed with status #{response.code}: #{response.message}"
        raise ApiError, "API request failed with status #{response.code}: #{response.message}"
      end

    rescue HTTParty::Error => e
      Rails.logger.error "❌ HTTP error for #{@org_number}: #{e.class} - #{e.message}"
      raise ApiError, "HTTP error: #{e.message}"
    rescue SocketError => e
      Rails.logger.error "❌ Network error for #{@org_number}: #{e.class} - #{e.message}"
      raise ApiError, "Network error: #{e.message}"
    rescue Net::ProtocolError => e
      Rails.logger.error "❌ Protocol error for #{@org_number}: #{e.class} - #{e.message}"
      raise ApiError, "Protocol error: #{e.message}"
    rescue RateLimitError => e
      Rails.logger.warn "⏰ Rate limited for #{@org_number}, retrying in #{e.retry_after}s..."
      raise # Re-raise rate limit errors for retry logic
    rescue JSON::ParserError => e
      Rails.logger.error "❌ Failed to parse response for #{@org_number}: #{e.message}"
      raise InvalidResponseError, "Invalid JSON response"
    rescue => e
      Rails.logger.error "❌ Unexpected error for #{@org_number}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      raise ApiError, "Unexpected error: #{e.message}"
    end
  end

  def parse_response(response_data)
    return {} if response_data.blank?
    # If response_data is an HTTParty::Response, parse its body
    if defined?(HTTParty::Response) && response_data.is_a?(HTTParty::Response)
      if response_data.body.nil? || response_data.body.empty?
        return {}
      end
      begin
        response_data = JSON.parse(response_data.body)
      rescue JSON::ParserError => e
        Rails.logger.error "❌ Failed to parse response body: #{e.message}"
        raise InvalidResponseError, "Invalid JSON response"
      end
    end
    Rails.logger.debug "📊 Starting to parse response data: #{response_data.inspect}"

    begin
      Rails.logger.debug "📊 Extracting financial data from response"

      # The API returns an array of financial records, get the first (most recent) one
      financial_record = if response_data.is_a?(Array) && response_data.any?
        Rails.logger.info "📄 Found #{response_data.length} financial record(s), using the first one"
        response_data.first
      elsif response_data.is_a?(Hash)
        Rails.logger.info "📄 Response is a single financial record"
        response_data
      else
        Rails.logger.info "ℹ️ No financial data found in response"
        return {}
      end

      # Extract financial data with proper error handling
      financials = {}

      begin
        financials = {
          operating_revenue: safe_dig(financial_record, "resultatregnskapResultat", "driftsresultat", "driftsinntekter", "sumDriftsinntekter"),
          ordinary_result: safe_dig(financial_record, "resultatregnskapResultat", "ordinaertResultatFoerSkattekostnad"),
          annual_result: safe_dig(financial_record, "resultatregnskapResultat", "aarsresultat"),
          operating_costs: safe_dig(financial_record, "resultatregnskapResultat", "driftsresultat", "driftskostnad", "sumDriftskostnad")
        }.compact

        Rails.logger.debug "💰 Extracted financials: #{financials.inspect}"

        # Convert all numeric values to BigDecimal
        result = financials.transform_values do |v|
          if v.is_a?(Numeric)
            v.to_d
          elsif v.is_a?(String) && v =~ /\A-?\d+(\.\d+)?\z/
            v.to_d
          else
            v
          end
        end

        Rails.logger.info "✅ Successfully parsed financial data for #{@org_number}: #{result.keys.join(', ')}"
        Rails.logger.debug "💰 After numeric conversion: #{result.inspect}"
        result

      rescue => e
        Rails.logger.error "❌ Error extracting financial data: #{e.class} - #{e.message}"
        Rails.logger.error "📍 Backtrace: #{e.backtrace.first(5).join("\n")}"
        raise InvalidResponseError, "Error extracting financial data: #{e.message}"
      end

    rescue InvalidResponseError => e
      # Re-raise our custom error
      raise
    rescue => e
      Rails.logger.error "❌ Unexpected error parsing response: #{e.class} - #{e.message}"
      Rails.logger.error "📍 Backtrace: #{e.backtrace.first(5).join("\n")}"
      raise InvalidResponseError, "Unexpected error parsing response: #{e.message}"
    end
  end

  # Global rate limiting using Redis - ensures only 1 API call per second across ALL threads
  def enforce_rate_limit!
    require "sidekiq"

    Sidekiq.redis do |redis|
      rate_limit_key = "company_financials_service:global_api_lock"
      last_call_key = "company_financials_service:last_api_call"

      # Try to acquire the rate limit slot
      acquired = false
      start_time = Time.now

      # Keep trying for up to 30 seconds to get a slot
      while Time.now - start_time < 30
        # Check when the last API call was made
        last_call_str = redis.get(last_call_key)
        last_call = last_call_str ? last_call_str.to_f : 0
        current_time = Time.now.to_f

        # If enough time has passed since the last call, try to acquire the lock
        if current_time - last_call >= 1.0
          # Try to acquire a 2-second lock to prevent race conditions
          if redis.set(rate_limit_key, current_time, nx: true, ex: 2)
            # Successfully acquired the lock, now record this API call time
            redis.set(last_call_key, current_time, ex: 10)
            acquired = true
            break
          end
        end

        # Wait a bit before trying again (with some jitter to avoid thundering herd)
        sleep(0.1 + rand(0.05))
      end

      unless acquired
        raise RateLimitError.new("Could not acquire rate limit slot after 30 seconds - too many concurrent requests", 30)
      end

      # We now have the exclusive right to make an API call
      Rails.logger.info "🔓 Acquired rate limit slot for API call"
    end
  end

  # Safely dig through nested hashes and arrays without raising errors
  def safe_dig(hash, *keys)
    return nil if hash.nil?

    keys.inject(hash) do |memo, key|
      if memo.is_a?(Hash) && memo.key?(key.to_s)
        memo[key.to_s]
      elsif memo.is_a?(Hash) && memo.key?(key.to_sym)
        memo[key.to_sym]
      elsif memo.is_a?(Array) && key.is_a?(Integer) && key >= 0 && key < memo.length
        memo[key]
      elsif memo.is_a?(Array) && key.respond_to?(:to_i) && key.to_i >= 0 && key.to_i < memo.length
        memo[key.to_i]
      else
        return nil
      end
    end
  rescue => e
    Rails.logger.error "❌ Error in safe_dig: #{e.class} - #{e.message}"
    Rails.logger.error "📍 Path: #{keys.inspect}"
    Rails.logger.error "📄 Current value: #{memo.inspect}" if defined?(memo)
    nil
  end

  def update_company_financials(financials, raw_response = nil)
    # Filter out any nil values to prevent setting fields to nil
    update_attrs = financials.compact

    # Add the raw API response if provided
    if raw_response.present?
      update_attrs[:financial_data] = raw_response
    end

    changed_fields = []

    # Only update if we have fields to update
    if update_attrs.any?
      # Track which fields are actually changing
      changed_fields = update_attrs.keys.select do |field|
        @company.send(field) != update_attrs[field]
      end

      if changed_fields.any?
        @company.update!(update_attrs)
        Rails.logger.info "✅ Updated financial data for #{@org_number}. Changed fields: #{changed_fields.join(', ')}"
        
        # Broadcast the update via ActionCable
        broadcast_financial_update(changed_fields, financials)
      else
        Rails.logger.info "ℹ️ No changes in financial data for #{@org_number}"
      end
    else
      Rails.logger.warn "⚠️ No financial data to update for #{@org_number}"
    end

    # Return the list of changed fields
    changed_fields
  end

  def publish_to_kafka(financials)
    return unless defined?(Kafka) && ENV["KAFKA_ENABLED"] == "true"

    begin
      message = {
        event_type: "company.financials.updated",
        timestamp: Time.current.iso8601,
        company_id: @company.id,
        registration_number: @org_number,
        data: financials.merge(
          company_name: @company.company_name,
          last_updated: Time.current.iso8601
        )
      }

      # Replace with your actual Kafka producer implementation
      # Example: KAFKA_PRODUCER.produce(message.to_json, topic: 'company_financials', key: @org_number)
      Rails.logger.info "📨 Would publish to company_financials: #{message.to_json}"
    rescue => e
      Rails.logger.error "❌ Failed to publish to Kafka: #{e.message}"
    end
  end

  def broadcast_financial_update(changed_fields, financials)
    return unless defined?(CompanyFinancialsChannel)
    
    begin
      Rails.logger.info "📺 Broadcasting financial update for company #{@company.id}"
      
      CompanyFinancialsChannel.broadcast_financial_update(@company, {
        status: 'success',
        changed_fields: changed_fields,
        financials: financials,
        company_id: @company.id,
        registration_number: @org_number
      })
    rescue => e
      Rails.logger.error "❌ Failed to broadcast financial update: #{e.message}"
    end
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