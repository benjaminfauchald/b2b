require "ostruct"
require "net/http"
require "json"
require "uri"
require "set"

class CompanyEmployeeDiscoveryService < ApplicationService
  def initialize(company = nil)
    @company = company
    super(service_name: "company_employee_discovery", action: "process")
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Company not found or not provided") unless @company

    audit_service_operation(@company) do |audit_log|
      unless needs_update?
        audit_log.update!(
          status: :success,
          metadata: audit_log.metadata.merge(reason: "up_to_date", skipped: true, status_type: "skipped"),
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
        )
        # Early return to avoid API call
        next success_result("Employee discovery data is up to date")
      end

      # Search for employees
      response = search_employees
      Rails.logger.debug "Employee Search Response: #{response.inspect}" if Rails.env.test?

      if response[:success]
        # Validate the employee data
        unless valid_employee_data?(response[:data])
          raise StandardError.new("Invalid employee data structure")
        end

        update_company_employees(response[:data])

        # Add metadata for successful API response
        audit_log.add_metadata(
          api_response_code: 200,
          employees_found: response[:data][:total_found],
          sources_used: configured_sources,
          by_source: response[:data][:by_source]
        )

        if response[:partial_failures]
          audit_log.add_metadata(partial_failures: response[:partial_failures])
          audit_log.add_metadata(errors: response[:data][:errors]) if response[:data][:errors]
          success_result("Partial success: Employee discovery completed with some source failures", discovered_employees: response[:data])
        elsif response[:data][:total_found] == 0
          success_result("No employees found", discovered_employees: response[:data])
        else
          success_result("Employee discovery successful", discovered_employees: response[:data])
        end
      elsif response[:rate_limited]
        # Create a custom exception that includes the retry_after info
        error = StandardError.new("API rate limit exceeded")
        error.define_singleton_method(:retry_after) { response[:retry_after] }
        raise error
      else
        raise StandardError.new(response[:error] || "Failed to search employees")
      end
    end
  rescue StandardError => e
    # For rate limit errors, include retry_after in the result data
    if e.message.include?("rate limit") && e.respond_to?(:retry_after)
      error_result(e.message, retry_after: e.retry_after)
    else
      error_result("Service error: #{e.message}")
    end
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "company_employee_discovery")
    config&.active?
  end

  def needs_update?
    # Use the ServiceAuditable concern's needs_service? method which checks audit logs
    @company.needs_service?("company_employee_discovery")
  end

  def search_employees
    sources = configured_sources
    discovered_employees = []
    total_found = 0
    by_source = {}
    errors = {}
    rate_limited = false
    retry_after = nil

    sources.each do |source|
      begin
        result = search_from_source(source)

        if result[:success]
          employees = result[:data][:employees] || []
          discovered_employees.concat(employees)
          by_source[source] = employees.count
          total_found += employees.count
        elsif result[:rate_limited]
          rate_limited = true
          retry_after = result[:retry_after]
          errors[source] = "Rate limited"
          break # Stop processing other sources if rate limited
        else
          errors[source] = result[:error]
          by_source[source] = 0
        end
      rescue StandardError => e
        errors[source] = e.message
        by_source[source] = 0
      end
    end

    # Deduplicate employees based on name and email
    unique_employees = deduplicate_employees(discovered_employees)

    # Validate emails
    unique_employees.each do |employee|
      employee[:email_valid] = valid_email?(employee[:email]) if employee[:email]
    end

    # Identify key contacts
    key_contacts = identify_key_contacts(unique_employees)

    response_data = {
      total_found: unique_employees.count,
      by_source: by_source,
      employees: unique_employees,
      key_contacts: key_contacts
    }

    response_data[:errors] = errors if errors.any?

    if rate_limited
      { success: false, rate_limited: true, retry_after: retry_after }
    elsif errors.any? && unique_employees.empty?
      { success: false, error: "All sources failed: #{errors.values.join(', ')}" }
    elsif errors.any?
      { success: true, data: response_data, partial_failures: errors.keys }
    else
      { success: true, data: response_data }
    end
  end

  def search_from_source(source)
    case source
    when "linkedin"
      search_linkedin_employees
    when "company_websites"
      search_website_employees
    when "public_registries"
      search_registry_employees
    else
      { success: false, error: "Unknown source: #{source}" }
    end
  end

  def search_linkedin_employees
    api_endpoint = ENV["LINKEDIN_API_ENDPOINT"] || "http://linkedin"
    uri = URI("#{api_endpoint}/company/#{@company.registration_number}/employees")

    response = Net::HTTP.get_response(uri)

    case response.code.to_i
    when 200
      data = JSON.parse(response.body, symbolize_names: true)
      employees = data[:employees] || []
      { success: true, data: { employees: employees } }
    when 429
      retry_after = response["Retry-After"]&.to_i || 3600
      { success: false, rate_limited: true, retry_after: retry_after }
    when 503
      { success: false, error: "API temporarily unavailable" }
    else
      { success: false, error: "API error: #{response.code}" }
    end
  rescue StandardError => e
    { success: false, error: "Request failed: #{e.message}" }
  end

  def search_website_employees
    return { success: false, error: "No website available" } unless @company.website.present?

    api_endpoint = ENV["WEB_SCRAPER_API"] || "http://scrape"
    uri = URI("#{api_endpoint}/scrape?url=#{URI.encode_www_form_component(@company.website)}")

    response = Net::HTTP.get_response(uri)

    case response.code.to_i
    when 200
      data = JSON.parse(response.body, symbolize_names: true)
      employees = data[:employees] || []
      { success: true, data: { employees: employees } }
    when 429
      retry_after = response["Retry-After"]&.to_i || 3600
      { success: false, rate_limited: true, retry_after: retry_after }
    else
      { success: false, error: "API error: #{response.code}" }
    end
  rescue StandardError => e
    { success: false, error: "Request failed: #{e.message}" }
  end

  def search_registry_employees
    api_endpoint = ENV["BRREG_API_ENDPOINT"] || "http://brreg"
    uri = URI("#{api_endpoint}/roller/#{@company.registration_number}")

    response = Net::HTTP.get_response(uri)

    case response.code.to_i
    when 200
      data = JSON.parse(response.body, symbolize_names: true)
      board_members = data[:board_members] || []
      # Convert board members to employee format
      employees = board_members.map do |member|
        {
          name: member[:name],
          title: member[:role] || member[:title],
          source: "public_registries",
          confidence: 1.0
        }
      end
      { success: true, data: { employees: employees } }
    when 429
      retry_after = response["Retry-After"]&.to_i || 3600
      { success: false, rate_limited: true, retry_after: retry_after }
    else
      { success: false, error: "API error: #{response.code}" }
    end
  rescue StandardError => e
    { success: false, error: "Request failed: #{e.message}" }
  end

  def configured_sources
    config = ServiceConfiguration.find_by(service_name: "company_employee_discovery")
    sources = config&.get_setting("sources") || [ "linkedin", "company_websites", "public_registries" ]
    sources
  end

  def deduplicate_employees(employees)
    # Simple deduplication based on name (case insensitive)
    unique_employees = []
    seen_names = Set.new

    employees.each do |employee|
      name_key = employee[:name]&.downcase&.strip
      next if name_key.blank? || seen_names.include?(name_key)

      seen_names.add(name_key)
      unique_employees << employee
    end

    unique_employees
  end

  def identify_key_contacts(employees)
    key_contacts = {}

    employees.each do |employee|
      title = employee[:title]&.downcase
      next unless title

      # Prioritize more specific titles and don't overwrite if already found
      if (title.include?("ceo") || title.include?("chief executive")) && !key_contacts[:ceo]
        key_contacts[:ceo] = employee[:name]
      elsif (title.include?("cto") || title.include?("chief technology")) && !key_contacts[:cto]
        key_contacts[:cto] = employee[:name]
      elsif (title.include?("cfo") || title.include?("chief financial")) && !key_contacts[:cfo]
        key_contacts[:cfo] = employee[:name]
      end
    end

    key_contacts
  end

  def valid_email?(email)
    return false if email.blank?
    email.include?("@") && email.include?(".")
  end

  def valid_employee_data?(data)
    data.is_a?(Hash) && data.key?(:employees) && data[:employees].is_a?(Array)
  end

  def update_company_employees(data)
    @company.update!(
      employees_data: data.to_json,
      employee_discovery_updated_at: Time.current
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

  def error_result(message, extra_attributes = {})
    result_attributes = {
      success?: false,
      message: nil,
      error: message,
      data: extra_attributes
    }

    # Add any extra attributes directly to the result
    extra_attributes.each do |key, value|
      result_attributes[key] = value unless result_attributes.key?(key)
    end

    OpenStruct.new(result_attributes)
  end
end
