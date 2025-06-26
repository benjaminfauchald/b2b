require "net/http"
require "json"
require "uri"
require "ostruct"

class PersonProfileExtractionService < ApplicationService
  include HTTParty
  
  def initialize(company_id:, **options)
    @company_id = company_id
    @company = Company.find(company_id)
    @phantom_id = ENV["PHANTOMBUSTER_PHANTOM_ID"]
    @api_key = ENV["PHANTOMBUSTER_API_KEY"]
    @base_url = "https://api.phantombuster.com/api/v2"
    super(service_name: "person_profile_extraction", action: "extract", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Missing PhantomBuster configuration") unless phantombuster_configured?
    
    linkedin_url = @company.best_linkedin_url
    return error_result("Company has no valid LinkedIn URL") unless linkedin_url.present?

    audit_service_operation(@company) do |audit_log|
      url_source = @company.linkedin_url.present? ? "manual" : "AI-discovered"
      confidence_info = @company.linkedin_ai_confidence.present? ? " (#{@company.linkedin_ai_confidence}% confidence)" : ""
      
      Rails.logger.info "🚀 Starting LinkedIn Profile Extraction for #{@company.company_name}"
      Rails.logger.info "📎 Using #{url_source} LinkedIn URL: #{linkedin_url}#{confidence_info}"
      
      # Update phantom configuration with best available LinkedIn URL
      update_phantom_configuration(@company.company_name, linkedin_url)
      
      # Launch phantom and monitor execution
      container_id = launch_phantom
      audit_log.add_metadata(
        container_id: container_id, 
        phantom_id: @phantom_id,
        linkedin_url: linkedin_url,
        url_source: url_source,
        linkedin_ai_confidence: @company.linkedin_ai_confidence
      )
      
      # Monitor execution until completion
      execution_result = monitor_phantom_execution(container_id)
      
      if execution_result[:success]
        # Fetch and save the extracted profiles
        profile_count = fetch_and_save_results(execution_result[:json_url], container_id)
        
        audit_log.add_metadata(
          profiles_extracted: profile_count,
          execution_time_seconds: execution_result[:execution_time],
          json_url: execution_result[:json_url]
        )
        
        success_result("Profile extraction completed", 
                      profiles_extracted: profile_count,
                      container_id: container_id)
      else
        error_result("Profile extraction failed: #{execution_result[:error]}")
      end
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "person_profile_extraction")
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
      headers: { 'X-Phantombuster-Key-1' => @api_key },
      timeout: 10
    )
    
    raise "Failed to fetch phantom config: #{response.code}" unless response.success?
    
    current_config = response.parsed_response
    argument_obj = if current_config['argument'].is_a?(String)
                    JSON.parse(current_config['argument'])
                  else
                    current_config['argument'] || {}
                  end
    
    # Update with company LinkedIn URL
    updated_argument_obj = argument_obj.merge('spreadsheetUrl' => company_url)
    
    updated_argument = if current_config['argument'].is_a?(String)
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
        'X-Phantombuster-Key-1' => @api_key,
        'Content-Type' => 'application/json'
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
        'X-Phantombuster-Key-1' => @api_key,
        'Content-Type' => 'application/json'
      },
      timeout: 10
    )
    
    raise "Failed to launch phantom: #{launch_response.code}" unless launch_response.success?
    
    container_id = launch_response.parsed_response['containerId']
    Rails.logger.info "📦 Phantom launched with container ID: #{container_id}"
    
    container_id
  end

  def monitor_phantom_execution(container_id)
    start_time = Time.current
    status = 'running'
    poll_count = 0
    
    Rails.logger.info "🔄 Monitoring phantom execution..."
    
    while status == 'running'
      poll_count += 1
      elapsed = (Time.current - start_time).to_i
      
      Rails.logger.info "🔄 Poll attempt #{poll_count} (#{elapsed}s elapsed)"
      
      if elapsed > 1800 # 30 minute timeout
        Rails.logger.error '⏰ Timeout reached (30 minutes)'
        return { success: false, error: 'Phantom execution timeout after 30 minutes' }
      end
      
      sleep(10)
      
      status_response = HTTParty.get(
        "#{@base_url}/containers/fetch",
        query: { id: container_id },
        headers: { 'X-Phantombuster-Key-1' => @api_key },
        timeout: 10
      )
      
      if status_response.success?
        status = status_response.parsed_response['status']
        Rails.logger.info "📊 Current status: #{status}"
      end
    end
    
    execution_time = (Time.current - start_time).to_i
    Rails.logger.info "⏰ Phantom execution completed in #{execution_time} seconds with status: #{status}"
    
    # Check for success
    success_statuses = ['success', 'finished', 'completed']
    failure_statuses = ['error', 'failed', 'timeout', 'cancelled']
    
    if failure_statuses.include?(status)
      return { success: false, error: "Phantom execution failed with status: #{status}" }
    end
    
    # Get output to extract result URLs
    output_response = HTTParty.get(
      "#{@base_url}/containers/fetch-output",
      query: { id: container_id },
      headers: { 'X-Phantombuster-Key-1' => @api_key },
      timeout: 10
    )
    
    raise "Failed to fetch output: #{output_response.code}" unless output_response.success?
    
    output = output_response.parsed_response['output']
    json_url = extract_json_url_from_output(output)
    
    if json_url
      { success: true, json_url: json_url, execution_time: execution_time }
    else
      { success: false, error: 'Could not find JSON result URL in phantom output' }
    end
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
      Rails.logger.info '⚠️ No profiles found'
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
            name: profile['fullName'] || profile['name'],
            title: profile['title'],
            location: profile['location'],
            profile_url: profile['linkedInProfileUrl'] || profile['profileUrl'] || profile['profile_url'],
            email: profile['email'],
            phone: profile['phone'],
            connection_degree: profile['connectionDegree'] || profile['connection_degree'],
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