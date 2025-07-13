require "net/http"
require "json"
require "uri"
require "ostruct"

class PersonProfileExtractionWebhookService < ApplicationService
  include HTTParty

  def initialize(company_id: nil, company: nil, webhook_url: nil, queue_job_id: nil, **options)
    @company_id = company_id
    @company = company || (company_id ? Company.find(company_id) : nil)
    @webhook_url = webhook_url
    @queue_job_id = queue_job_id
    @phantom_id = ENV["PHANTOMBUSTER_PHANTOM_ID"]
    @api_key = ENV["PHANTOMBUSTER_API_KEY"]
    @base_url = "https://api.phantombuster.com/api/v2"
    super(service_name: "phantom_buster_profile_extraction", action: "extract_with_webhook", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Missing PhantomBuster configuration") unless phantombuster_configured?
    return error_result("Company not found or not provided") unless @company
    return error_result("Webhook URL is required for webhook mode") unless @webhook_url.present?
    
    linkedin_url = @company.best_linkedin_url
    return error_result("Company has no valid LinkedIn URL") unless linkedin_url.present?

    # Use proper SCT pattern with audit_service_operation
    audit_service_operation(@company) do |audit_log|
      url_source = @company.linkedin_url.present? ? "manual" : "AI-discovered"
      confidence_info = @company.linkedin_ai_confidence.present? ? " (#{@company.linkedin_ai_confidence}% confidence)" : ""

      Rails.logger.info "🚀 Starting LinkedIn Profile Extraction (WEBHOOK MODE) for #{@company.company_name}"
      Rails.logger.info "📎 Using #{url_source} LinkedIn URL: #{linkedin_url}#{confidence_info}"
      Rails.logger.info "🔗 Webhook URL: #{@webhook_url}"

      # Add initial metadata to audit log
      audit_log.add_metadata(
        linkedin_url: linkedin_url,
        url_source: url_source,
        linkedin_ai_confidence: @company.linkedin_ai_confidence,
        status: "initializing",
        phantom_id: @phantom_id,
        webhook_url: @webhook_url,
        queue_job_id: @queue_job_id,
        processing_mode: "webhook"
      )

      # Update phantom configuration with webhook URL and LinkedIn URL
      update_phantom_configuration_with_webhook(@company.company_name, linkedin_url, @webhook_url)

      # Launch phantom
      container_id = launch_phantom

      # Check if launch was successful
      if container_id.nil? || container_id.blank?
        audit_log.add_metadata(
          error: "Failed to launch PhantomBuster - no container ID returned",
          launch_attempted_at: Time.current.iso8601
        )
        raise "Failed to launch PhantomBuster - no container ID returned"
      end

      # Store container ID in audit log for webhook tracking
      audit_log.add_metadata(
        phantom_container_id: container_id,
        status: "phantom_launched",
        launched_at: Time.current.iso8601
      )

      # No polling needed - webhook will handle completion
      Rails.logger.info "🔗 PhantomBuster configured for webhook completion. Container ID: #{container_id}"

      # Return immediately with pending status
      success_result("Profile extraction launched with webhook mode. Will be notified on completion.",
                    container_id: container_id,
                    audit_log_id: audit_log.id,
                    status: "webhook_pending")
    end
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: 'person_profile_extraction')
    return false unless config
    config.active?
  end

  def phantombuster_configured?
    @phantom_id.present? && @api_key.present?
  end

  def update_phantom_configuration_with_webhook(company_name, company_url, webhook_url)
    Rails.logger.info "🔧 Updating Phantom configuration with URL: #{company_url} and webhook: #{webhook_url}"

    # Get current configuration
    response = HTTParty.get(
      "#{@base_url}/agents/fetch",
      query: { id: @phantom_id },
      headers: { "X-Phantombuster-Key-1" => @api_key },
      timeout: 10
    )

    raise "Failed to fetch phantom config: #{response.code}" unless response.success?

    current_config = response.parsed_response
    argument_obj = if current_config["argument"].is_a?(String)
                    JSON.parse(current_config["argument"])
    else
                    current_config["argument"] || {}
    end

    # Update with company LinkedIn URL and webhook
    updated_argument_obj = argument_obj.merge(
      "spreadsheetUrl" => company_url,
      "webhookUrl" => webhook_url,
      "enableWebhooks" => true
    )

    updated_argument = if current_config["argument"].is_a?(String)
                        JSON.generate(updated_argument_obj)
    else
                        updated_argument_obj
    end

    # Save updated configuration
    save_response = HTTParty.post(
      "#{@base_url}/agents/save",
      body: {
        id: @phantom_id,
        argument: updated_argument
      }.to_json,
      headers: {
        "X-Phantombuster-Key-1" => @api_key,
        "Content-Type" => "application/json"
      },
      timeout: 10
    )

    raise "Failed to save phantom config: #{save_response.code}" unless save_response.success?

    Rails.logger.info "✅ Updated Phantom config with webhook URL successfully"
  end

  def launch_phantom
    Rails.logger.info "🚀 Launching PhantomBuster phantom with webhook mode..."

    # Configure launch with webhook settings
    launch_body = {
      id: @phantom_id,
      webhook: @webhook_url # Some PhantomBuster versions support webhook in launch
    }

    launch_response = HTTParty.post(
      "#{@base_url}/agents/launch",
      body: launch_body.to_json,
      headers: {
        "X-Phantombuster-Key-1" => @api_key,
        "Content-Type" => "application/json"
      },
      timeout: 10
    )

    unless launch_response.success?
      Rails.logger.error "❌ Failed to launch phantom: HTTP #{launch_response.code} - #{launch_response.body}"
      
      # Check for rate limiting specifically
      if launch_response.code == 429
        raise "RuntimeError: Failed to launch phantom: 429 - Too Many Requests"
      end
      
      raise "Failed to launch phantom: #{launch_response.code} - #{launch_response.message}"
    end

    container_id = launch_response.parsed_response["containerId"]

    if container_id.nil? || container_id.blank?
      Rails.logger.error "❌ PhantomBuster API returned success but no container ID"
      Rails.logger.error "Response body: #{launch_response.body}"
      return nil
    end

    Rails.logger.info "📦 Phantom launched with container ID: #{container_id} (webhook mode)"
    container_id
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    Rails.logger.error "❌ PhantomBuster API timeout: #{e.message}"
    raise "PhantomBuster API timeout: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "❌ Unexpected error launching phantom: #{e.class} - #{e.message}"
    raise
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