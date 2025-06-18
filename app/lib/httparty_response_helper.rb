# frozen_string_literal: true

module HttpartyResponseHelper
  extend ActiveSupport::Concern

  # Check if HTTParty response is valid and has content
  def valid_response?(response)
    return false if response.body.nil? || response.body.empty?
    return false unless response.respond_to?(:success?) && response.success?
    true
  end

  # Safe response body extraction
  def safe_response_body(response)
    return nil unless valid_response?(response)
    response.body.strip
  end

  # Parse JSON response safely
  def parse_json_response(response)
    return nil unless valid_response?(response)

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Rails.logger.warn "JSON parsing failed: #{e.message}"
      nil
    end
  end

  # Handle HTTParty requests consistently
  def handle_httparty_request(url, options = {}, &block)
    default_options = {
      timeout: 30,
      headers: {
        "User-Agent" => "B2B-Services/1.0",
        "Accept" => "application/json"
      },
      # Add SSL verification
      verify: Rails.env.production?,
      debug_output: Rails.env.development? ? $stdout : nil
    }

    begin
      merged_options = default_options.merge(options)

      Rails.logger.debug "[HTTParty] Making request to: #{url}"
      Rails.logger.debug "[HTTParty] Request options: #{merged_options.except(:debug_output).inspect}"

      response = HTTParty.get(url, merged_options)

      Rails.logger.debug "[HTTParty] Response code: #{response&.code}"
      Rails.logger.debug "[HTTParty] Response headers: #{response&.headers&.inspect}"

      if block_given?
        if valid_response?(response)
          yield(response)
        else
          Rails.logger.warn "[HTTParty] Invalid response for #{url}: #{response&.code} - #{response&.message}"
          nil
        end
      else
        valid_response?(response) ? response : nil
      end

    rescue HTTParty::Error => e
      Rails.logger.error "[HTTParty] HTTP error for #{url}: #{e.class} - #{e.message}"
      nil
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "[HTTParty] Timeout error for #{url}: #{e.class} - #{e.message}"
      nil
    rescue SocketError => e
      Rails.logger.error "[HTTParty] Socket error for #{url}: #{e.class} - #{e.message}"
      Rails.logger.error "[HTTParty] This usually indicates a DNS resolution issue or network connectivity problem"
      nil
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET => e
      Rails.logger.error "[HTTParty] Network error for #{url}: #{e.class} - #{e.message}"
      nil
    rescue OpenSSL::SSL::SSLError => e
      Rails.logger.error "[HTTParty] SSL error for #{url}: #{e.class} - #{e.message}"
      nil
    rescue => e
      Rails.logger.error "[HTTParty] Unexpected error for #{url}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      nil
    end
  end

  # Get response status info
  def response_status_info(response)
    return { valid: false, message: "Response body is empty" } if response.body.nil? || response.body.empty?
    return { valid: false, message: "HTTP #{response.code}: #{response.message}" } unless response.respond_to?(:success?) && response.success?

    { valid: true, message: "Success" }
  end
end
