class CompanyFinancialsService
  include HttpartyResponseHelper

  BASE_URL = "https://data.brreg.no/regnskapsregisteret/regnskap".freeze
  MAX_ATTEMPTS = 3
  INITIAL_RETRY_DELAY = 2 # seconds
  SERVICE_NAME = "company_financials"

  class ApiError < StandardError; end
  class RateLimitError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after = nil)
      super(message)
      @retry_after = retry_after
    end
  end
  class InvalidResponseError < StandardError; end

  def initialize(company)
    @company = company
    @org_number = company.registration_number
    @logger = Rails.logger
    @attempts = 0
    puts " Service Name: #{SERVICE_NAME}"
  end

  def call
    return { changed_fields: [], success: false } unless @org_number.present?

    @start_time = Time.current
    @audit_log = ServiceAuditLog.create!(
      auditable: @company,
      service_name: "company_financials",
      operation_type: "update",
      status: :pending,
      started_at: Time.current,
      table_name: "companies",
      record_id: @company.id,
      columns_affected: [ "none" ],
      metadata: { error: "no metadata" }
    )

    begin
      result = fetch_and_update_financials
      @audit_log.mark_success!(
        {
          company_id: @company.id,
          registration_number: @org_number,
          changed_fields: result[:changed_fields] || []
        },
        result[:changed_fields] || []
      )
      result
    rescue RateLimitError => e
      @audit_log.mark_failed!(
        e.message,
        {
          error: e.message,
          company_id: @company.id,
          registration_number: @org_number
        },
        []
      )
      raise
    rescue ApiError => e
      @audit_log.mark_failed!(
        e.message,
        {
          error: e.message,
          company_id: @company.id,
          registration_number: @org_number
        },
        []
      )
      raise
    rescue StandardError => e
      @audit_log.mark_failed!(
        e.message,
        {
          error: e.message,
          company_id: @company.id,
          registration_number: @org_number
        },
        []
      )
      raise
    end
  end

  private

  def fetch_and_update_financials
    @attempts ||= 0

    begin
      financial_data = make_api_request

      # If we got financial data, process it
      if financial_data.present?
        @logger.info "[#{SERVICE_NAME}] Successfully fetched financial data for #{@org_number}"
        process_financial_data(financial_data)
      else
        @logger.warn "[#{SERVICE_NAME}] No financial data available for #{@org_number}"
        { success: true, changed_fields: [], financials: {} }
      end

    rescue RateLimitError => e
      @logger.warn "[#{SERVICE_NAME}] Rate limited. Waiting #{e.retry_after} seconds..."
      sleep(e.retry_after)
      retry
    rescue ApiError, InvalidResponseError => e
      @logger.error "[#{SERVICE_NAME}] Error fetching financial data: #{e.message}"
      @attempts += 1

      if @attempts < MAX_ATTEMPTS
        retry_delay = INITIAL_RETRY_DELAY * (2 ** (@attempts - 1))
        @logger.info "[#{SERVICE_NAME}] Retrying in #{retry_delay} seconds... (Attempt #{@attempts + 1}/#{MAX_ATTEMPTS})"
        sleep(retry_delay)
        retry
      else
        @logger.error "[#{SERVICE_NAME}] Max retries reached for #{@org_number}"
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
      @logger.info "No financial data to process for #{@org_number}"
      { success: true, changed_fields: [], financials: {} }
    end
  end

  def make_api_request
    # Enforce global rate limiting before making the API call
    enforce_rate_limit!

    # Construct the full URL with the organization number
    url = "#{BASE_URL}/#{@org_number}"

    @logger.info "[#{SERVICE_NAME}] Fetching financial data for #{@org_number} - Attempt #{@attempts}/#{MAX_ATTEMPTS}"
    @logger.debug "[#{SERVICE_NAME}] Request URL: #{url}"

    begin
      # Add headers for the BRREG API
      headers = {
        "Accept" => "application/json",
        "User-Agent" => "B2B-Services/1.0",
        "Accept-Encoding" => "gzip, deflate, br"
      }

      @logger.debug "[#{SERVICE_NAME}] Request headers: #{headers.inspect}"

      # Make the request with a reasonable timeout
      response = handle_httparty_request(url, {
        headers: headers,
        timeout: 30,
        verify: true
      })

      # Check if response is nil (returned by handle_httparty_request for invalid responses)
      if response.nil?
        @logger.warn "[#{SERVICE_NAME}] No valid response received for #{@org_number} (likely 404 or network error)"
        return nil
      end

      # Explicitly check response body for nil or empty (HTTParty deprecation fix)
      if response.body.nil? || response.body.empty?
        @logger.warn "[#{SERVICE_NAME}] No valid response body received for #{@org_number}"
        return nil
      end

      @logger.debug "[#{SERVICE_NAME}] Response code: #{response.code}"
      @logger.debug "[#{SERVICE_NAME}] Response headers: #{response.headers.inspect}"

      # Check for rate limiting
      if response.code == 429
        retry_after = response.headers["Retry-After"]&.to_i || 60
        @logger.warn "[#{SERVICE_NAME}] Rate limited. Waiting #{retry_after} seconds..."
        raise RateLimitError.new("Rate limited", retry_after)
      end

      # Check if we have a successful response
      if response.success?
        # Parse the JSON response
        begin
          parsed_body = JSON.parse(response.body)
        rescue JSON::ParserError => e
          @logger.error "[#{SERVICE_NAME}] Failed to parse response for #{@org_number}: #{e.message}"
          raise InvalidResponseError, "Invalid JSON response"
        end

        @logger.debug "[#{SERVICE_NAME}] Parsed response: #{parsed_body.inspect}"

        # Parse the financial data from the response
        parsed_response = parse_response(parsed_body)

        if parsed_response.nil? || parsed_response.empty?
          @logger.info "[#{SERVICE_NAME}] No financial data found for #{@org_number}"
          return nil
        end

        # Return both parsed data and raw response
        { parsed_data: parsed_response, raw_response: response.body }
      else
        @logger.error "[#{SERVICE_NAME}] API request failed with status #{response.code}: #{response.message}"
        raise ApiError, "API request failed with status #{response.code}: #{response.message}"
      end

    rescue HTTParty::Error => e
      @logger.error "[#{SERVICE_NAME}] HTTP error for #{@org_number}: #{e.class} - #{e.message}"
      raise ApiError, "HTTP error: #{e.message}"
    rescue SocketError => e
      @logger.error "[#{SERVICE_NAME}] Network error for #{@org_number}: #{e.class} - #{e.message}"
      raise ApiError, "Network error: #{e.message}"
    rescue Net::ProtocolError => e
      @logger.error "[#{SERVICE_NAME}] Protocol error for #{@org_number}: #{e.class} - #{e.message}"
      raise ApiError, "Protocol error: #{e.message}"
    rescue RateLimitError => e
      @logger.warn "[#{SERVICE_NAME}] Rate limited for #{@org_number}, retrying in #{e.retry_after}s..."
      raise # Re-raise rate limit errors for retry logic
    rescue JSON::ParserError => e
      @logger.error "[#{SERVICE_NAME}] Failed to parse response for #{@org_number}: #{e.message}"
      raise InvalidResponseError, "Invalid JSON response"
    rescue => e
      @logger.error "[#{SERVICE_NAME}] Unexpected error for #{@org_number}: #{e.class} - #{e.message}"
      @logger.error e.backtrace.join("\n") if Rails.env.development?
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
        @logger.error "[#{SERVICE_NAME}] Failed to parse response body: #{e.message}"
        raise InvalidResponseError, "Invalid JSON response"
      end
    end
    @logger.debug "[#{SERVICE_NAME}] Starting to parse response data: #{response_data.inspect}"

    begin
      @logger.debug "[#{SERVICE_NAME}] Extracting financial data from response"

      # The API returns an array of financial records, get the first (most recent) one
      financial_record = if response_data.is_a?(Array) && response_data.any?
        @logger.info "[#{SERVICE_NAME}] Found #{response_data.length} financial record(s), using the first one"
        response_data.first
      elsif response_data.is_a?(Hash)
        @logger.info "[#{SERVICE_NAME}] Response is a single financial record"
        response_data
      else
        @logger.info "[#{SERVICE_NAME}] No financial data found in response"
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

        @logger.debug "[#{SERVICE_NAME}] Extracted financials: #{financials.inspect}"

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

        @logger.info "[#{SERVICE_NAME}] Successfully parsed financial data for #{@org_number}: #{result.keys.join(', ')}"
        @logger.debug "[#{SERVICE_NAME}] After numeric conversion: #{result.inspect}"
        result

      rescue => e
        @logger.error "[#{SERVICE_NAME}] Error extracting financial data: #{e.class} - #{e.message}"
        @logger.error "[#{SERVICE_NAME}] Backtrace: #{e.backtrace.first(5).join("\n")}"
        raise InvalidResponseError, "Error extracting financial data: #{e.message}"
      end

    rescue InvalidResponseError => e
      # Re-raise our custom error
      raise
    rescue => e
      @logger.error "[#{SERVICE_NAME}] Unexpected error parsing response: #{e.class} - #{e.message}"
      @logger.error "[#{SERVICE_NAME}] Backtrace: #{e.backtrace.first(5).join("\n")}"
      raise InvalidResponseError, "Unexpected error parsing response: #{e.message}"
    end
  end

  private

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
      @logger.info "[#{SERVICE_NAME}] Acquired rate limit slot for API call"
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
    @logger.error "[#{SERVICE_NAME}] Error in safe_dig: #{e.class} - #{e.message}"
    @logger.error "[#{SERVICE_NAME}] Path: #{keys.inspect}"
    @logger.error "[#{SERVICE_NAME}] Current value: #{memo.inspect}" if defined?(memo)
    nil
  end

  # Parse year from date string (YYYY-MM-DD)
  def parse_year(date_str)
    return nil unless date_str.is_a?(String)

    if (match = date_str.match(/^(\d{4})/))
      match[1].to_i
    end
  rescue => e
    @logger.warn "[#{SERVICE_NAME}] Failed to parse year from date: #{date_str} - #{e.message}"
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
        @logger.info "Updated financial data for #{@org_number}. Changed fields: #{changed_fields.join(', ')}"
        
        # Broadcast the update via ActionCable
        broadcast_financial_update(changed_fields, financials)
      else
        @logger.info "No changes in financial data for #{@org_number}"
      end
    else
      @logger.warn "No financial data to update for #{@org_number}"
    end

    # Return the list of changed fields
    changed_fields
  end

  def parse_error_message(response)
    # Try to parse error message from XML if response is XML
    if response.body.to_s.include?("<?xml")
      doc = Nokogiri::XML(response.body)
      doc.at_xpath("//message")&.text || "Unknown error"
    else
      response.message
    end
  rescue => e
    log_to_sct("ERROR_PARSING", [], "WARNING", 0, e.message, {
      response_code: response.code,
      response_body: response.body.to_s.truncate(500)
    })
    response.message
  end

  def log_to_sct(action, fields, status, duration_ms, error_message = nil, metadata = {})
    begin
      # Replace with your actual SCT logging implementation
      # Example: SCT.log(SERVICE_NAME, 'companies', 'companies', @company&.id, action, fields, status, duration_ms, error_message, metadata)
      Rails.logger.info("[SCT] #{action} - #{status} - #{error_message}")
      Rails.logger.debug("[SCT] Metadata: #{metadata.to_json}")
    rescue => e
      Rails.logger.error("Failed to log to SCT: #{e.message}")
    end
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
      Rails.logger.info("[KAFKA] Would publish to company_financials: #{message.to_json}")
    rescue => e
      Rails.logger.error("Failed to publish to Kafka: #{e.message}")
      @audit_log&.add_context(
        kafka_error: e.message,
        kafka_backtrace: e.backtrace.first(3)
      )
    end
  end

  def handle_rate_limit_retry(error)
    retry_after = error.retry_after || INITIAL_RETRY_DELAY
    @logger.warn "Rate limited. Retrying in #{retry_after} seconds..."
    sleep(retry_after)
  end

  def handle_rate_limit_error(error)
    error_msg = "Rate limit exceeded for #{@org_number} after #{@attempts} attempts"
    @logger.error error_msg

    @audit_log&.mark_failed!(
      "#{error.class.name}: #{error.message}",
      http_error: 429,
      http_error_message: "Rate limit exceeded. #{error.message}",
      attempt: @attempts
    )
  end

  def handle_api_error(error)
    @logger.error "API error for #{@org_number}: #{error.message}"

    @audit_log&.mark_failed!(
      "#{error.class.name}: #{error.message}",
      http_error: 500,
      http_error_message: error.message,
      attempt: @attempts
    )
  end

  def handle_unexpected_error(error)
    error_msg = "Unexpected error processing #{@org_number}: #{error.message}"
    @logger.error "#{error_msg}\n#{error.backtrace.first(5).join("\n")}"

    @audit_log&.mark_failed!(
      "#{error.class.name}: #{error.message}",
      http_error: 500,
      http_error_message: "Unexpected error: #{error.message}",
      backtrace: error.backtrace.first(5),
      attempt: @attempts
    )
  end

  def broadcast_financial_update(changed_fields, financials)
    return unless defined?(CompanyFinancialsChannel)
    
    begin
      @logger.info "[#{SERVICE_NAME}] Broadcasting financial update for company #{@company.id}"
      
      CompanyFinancialsChannel.broadcast_financial_update(@company, {
        status: 'success',
        changed_fields: changed_fields,
        financials: financials,
        company_id: @company.id,
        registration_number: @org_number
      })
    rescue => e
      @logger.error "[#{SERVICE_NAME}] Failed to broadcast financial update: #{e.message}"
    end
  end
end
