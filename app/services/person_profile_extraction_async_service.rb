require "net/http"
require "json"
require "uri"
require "ostruct"

class PersonProfileExtractionAsyncService < ApplicationService
  include HTTParty

  def initialize(company_id: nil, company: nil, **options)
    @company_id = company_id
    @company = company || (company_id ? Company.find(company_id) : nil)
    @phantom_id = ENV["PHANTOMBUSTER_PHANTOM_ID"]
    @api_key = ENV["PHANTOMBUSTER_API_KEY"]
    @base_url = "https://api.phantombuster.com/api/v2"
    super(service_name: "person_profile_extraction", action: "extract", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Missing PhantomBuster configuration") unless phantombuster_configured?
    return error_result("Company not found or not provided") unless @company
    
    linkedin_url = @company.best_linkedin_url
    return error_result("Company has no valid LinkedIn URL") unless linkedin_url.present?

    # Use proper SCT pattern with audit_service_operation
    audit_service_operation(@company) do |audit_log|
      url_source = @company.linkedin_url.present? ? "manual" : "AI-discovered"
      confidence_info = @company.linkedin_ai_confidence.present? ? " (#{@company.linkedin_ai_confidence}% confidence)" : ""

      Rails.logger.info "🚀 Starting LinkedIn Profile Extraction for #{@company.company_name}"
      Rails.logger.info "📎 Using #{url_source} LinkedIn URL: #{linkedin_url}#{confidence_info}"

      # Add initial metadata to audit log
      audit_log.add_metadata(
        linkedin_url: linkedin_url,
        url_source: url_source,
        linkedin_ai_confidence: @company.linkedin_ai_confidence,
        status: "initializing",
        phantom_id: @phantom_id
      )

      # Update phantom configuration with best available LinkedIn URL
      update_phantom_configuration(@company.company_name, linkedin_url)

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

      # Store container ID in audit log for async processing
      audit_log.add_metadata(
        container_id: container_id,
        status: "phantom_launched",
        launched_at: Time.current.iso8601
      )

      # Schedule async check job instead of synchronous monitoring
      schedule_status_check(container_id, audit_log.id)

      # Schedule monitor as additional safety net
      PhantomJobMonitorWorker.perform_in(11.minutes)

      # Return immediately with pending status - DO NOT mark as success yet
      # The audit_service_operation will handle marking as success/failed
      success_result("Profile extraction launched. Monitoring in background.",
                    container_id: container_id,
                    audit_log_id: audit_log.id,
                    status: "processing")
    end
  end

  # New method to check phantom status (called by async job)
  def check_phantom_status(container_id, audit_log_id)
    audit_log = ServiceAuditLog.find(audit_log_id)

    Rails.logger.info "🔍 Checking phantom status for container: #{container_id}"

    status_response = HTTParty.get(
      "#{@base_url}/containers/fetch",
      query: { id: container_id },
      headers: { "X-Phantombuster-Key-1" => @api_key },
      timeout: 10
    )

    return error_result("Failed to fetch container status") unless status_response.success?

    container = status_response.parsed_response
    status = container["status"]

    Rails.logger.info "📊 Container status: #{status}"

    case status
    when "running"
      # Still running, schedule another check
      schedule_status_check(container_id, audit_log_id, delay: 30.seconds)
      success_result("Still processing", status: "running")

    when "finished", "success"
      # Completed successfully, fetch and save results
      process_completed_phantom(container_id, audit_log)

    when "error", "failed", "timeout", "cancelled"
      # Failed - use SCT pattern for error handling
      audit_log.add_metadata(
        error: "Phantom execution failed with status: #{status}",
        phantom_status: status,
        ended_at: container["endedAt"]
      )
      audit_log.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: "Phantom execution failed with status: #{status}",
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
      )
      error_result("Phantom execution failed", status: status)

    else
      # Unknown status
      Rails.logger.warn "⚠️ Unknown phantom status: #{status}"
      schedule_status_check(container_id, audit_log_id, delay: 60.seconds)
      success_result("Unknown status, will retry", status: status)
    end
  rescue StandardError => e
    Rails.logger.error "❌ Error checking phantom status: #{e.message}"
    error_result("Status check error: #{e.message}")
  end

  private

  def process_completed_phantom(container_id, audit_log)
    Rails.logger.info "✅ Phantom completed, fetching results..."

    # Get output to extract result URLs
    output_response = HTTParty.get(
      "#{@base_url}/containers/fetch-output",
      query: { id: container_id },
      headers: { "X-Phantombuster-Key-1" => @api_key },
      timeout: 10
    )

    unless output_response.success?
      audit_log.add_metadata(
        error: "Failed to fetch phantom output"
      )
      audit_log.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: "Failed to fetch phantom output",
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
      )
      return error_result("Failed to fetch phantom output")
    end

    output = output_response.parsed_response["output"]
    json_url = extract_json_url_from_output(output)

    unless json_url
      audit_log.add_metadata(
        error: "Could not find JSON result URL in phantom output"
      )
      audit_log.update!(
        status: "failed",
        completed_at: Time.current,
        error_message: "Could not find JSON result URL in phantom output",
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
      )
      return error_result("No JSON URL found in output")
    end

    # Fetch and save results
    profile_count = fetch_and_save_results(json_url, container_id)

    # Update audit log with success using SCT pattern
    audit_log.add_metadata(
      profiles_extracted: profile_count,
      json_url: json_url,
      phantom_status: "finished",
      completed_at: Time.current.iso8601
    )
    
    # Mark as success - let ApplicationService handle the completion
    audit_log.update!(
      status: "success",
      completed_at: Time.current,
      execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
    )

    success_result("Profile extraction completed",
                  profiles_extracted: profile_count,
                  container_id: container_id)
  end

  def schedule_status_check(container_id, audit_log_id, delay: 10.seconds)
    Rails.logger.info "⏰ Scheduling status check in #{delay.to_i} seconds"
    PersonProfileExtractionStatusWorker.perform_in(delay, @company_id, container_id, audit_log_id)
  end

  def service_active?
    config = ServiceConfiguration.find_by(service_name: service_name)
    return false unless config
    config.active?
  end

  def phantombuster_configured?
    @phantom_id.present? && @api_key.present?
  end

  def update_phantom_configuration(company_name, company_url)
    Rails.logger.info "🔧 Updating Phantom configuration with URL: #{company_url}"

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

    # Update with company LinkedIn URL
    updated_argument_obj = argument_obj.merge("spreadsheetUrl" => company_url)

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

    Rails.logger.info "✅ Updated Phantom config successfully"
  end

  def launch_phantom
    Rails.logger.info "🚀 Launching PhantomBuster phantom..."

    launch_response = HTTParty.post(
      "#{@base_url}/agents/launch",
      body: { id: @phantom_id }.to_json,
      headers: {
        "X-Phantombuster-Key-1" => @api_key,
        "Content-Type" => "application/json"
      },
      timeout: 10
    )

    unless launch_response.success?
      Rails.logger.error "❌ Failed to launch phantom: HTTP #{launch_response.code} - #{launch_response.body}"
      raise "Failed to launch phantom: #{launch_response.code} - #{launch_response.message}"
    end

    container_id = launch_response.parsed_response["containerId"]

    if container_id.nil? || container_id.blank?
      Rails.logger.error "❌ PhantomBuster API returned success but no container ID"
      Rails.logger.error "Response body: #{launch_response.body}"
      return nil
    end

    Rails.logger.info "📦 Phantom launched with container ID: #{container_id}"
    container_id
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    Rails.logger.error "❌ PhantomBuster API timeout: #{e.message}"
    raise "PhantomBuster API timeout: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "❌ Unexpected error launching phantom: #{e.class} - #{e.message}"
    raise
  end

  def extract_json_url_from_output(output)
    # Try primary pattern
    json_match = output.match(/JSON saved at (https:\/\/[^\s\r\n]+\.json)/)
    return json_match[1] if json_match

    # Try alternative patterns
    alt_json_matches = output.scan(/https:\/\/[^\s\r\n]*\.json/)
    return alt_json_matches.last if alt_json_matches.any?

    nil
  end

  def fetch_and_save_results(json_url, container_id)
    Rails.logger.info "📥 Fetching results from: #{json_url}"

    response = HTTParty.get(json_url, timeout: 30)
    raise "Failed to fetch results: #{response.code}" unless response.success?

    profiles = response.parsed_response

    unless profiles.is_a?(Array) && profiles.any?
      Rails.logger.info "⚠️ No profiles found"
      return 0
    end

    Rails.logger.info "📊 Found #{profiles.length} profiles"
    save_profiles_to_database(profiles, container_id)
  end

  def save_profiles_to_database(profiles, phantom_run_id)
    inserted_count = 0
    skipped_count = 0

    ActiveRecord::Base.transaction do
      profiles.each do |profile|
        begin
          person = Person.create!(
            company_id: @company_id,
            company_name: @company.company_name,
            name: profile["fullName"] || profile["name"],
            title: profile["title"] || profile["jobTitle"],
            location: profile["location"],
            profile_url: profile["linkedInProfileUrl"] || profile["profileUrl"] || profile["profile_url"],
            email: profile["email"],
            phone: profile["phone"],
            connection_degree: profile["connectionDegree"] || profile["connection_degree"],
            phantom_run_id: phantom_run_id,
            profile_extracted_at: Time.current,
            profile_data: profile
          )

          inserted_count += 1

        rescue ActiveRecord::RecordNotUnique
          skipped_count += 1
        rescue => e
          Rails.logger.warn "⚠️ Failed to save profile: #{e.message}"
          skipped_count += 1
        end
      end
    end

    Rails.logger.info "✅ Saved #{inserted_count} profiles (#{skipped_count} duplicates skipped)"
    inserted_count
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
