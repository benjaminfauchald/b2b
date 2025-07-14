# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# LinkedIn Company Data Extractor
# Ruby implementation of the Python LinkedIn company data extraction functionality
# Extracts company names, IDs, and data from LinkedIn URLs and company identifiers
class LinkedinCompanyExtractor
  class AuthenticationError < StandardError; end
  class RateLimitError < StandardError; end
  class CompanyNotFoundError < StandardError; end

  attr_reader :linkedin_email, :linkedin_password, :li_at_cookie, :jsessionid_cookie

  def initialize(linkedin_email: nil, linkedin_password: nil, li_at_cookie: nil, jsessionid_cookie: nil)
    @linkedin_email = linkedin_email
    @linkedin_password = linkedin_password
    @li_at_cookie = li_at_cookie
    @jsessionid_cookie = jsessionid_cookie

    validate_credentials!
  end

  # Extract company identifier from LinkedIn URL
  # Supports both numeric IDs and slugs:
  # - https://www.linkedin.com/company/51649953 -> "51649953"
  # - https://www.linkedin.com/company/telenor-group/ -> "telenor-group"
  def extract_company_id_from_url(linkedin_url)
    return nil unless linkedin_url.present?

    uri = URI.parse(linkedin_url)
    path = uri.path.to_s.strip.gsub(/^\/|\/+$/, '')

    if path.start_with?('company/')
      company_identifier = path.sub('company/', '')
      return company_identifier.present? ? company_identifier : nil
    end

    nil
  rescue URI::InvalidURIError
    Rails.logger.error "LinkedinCompanyExtractor: Invalid LinkedIn URL: #{linkedin_url}"
    nil
  end

  # Check if identifier is a numeric LinkedIn ID
  def numeric_id?(identifier)
    identifier.to_s.match?(/^\d+$/)
  end

  # Extract company name from LinkedIn URL
  def extract_company_name_from_url(linkedin_url)
    company_identifier = extract_company_id_from_url(linkedin_url)
    return nil unless company_identifier

    company_data = get_company_data(company_identifier)
    company_data&.dig(:name)
  end

  # Get company ID from slug
  def get_company_id_from_slug(company_slug)
    company_data = get_company_data(company_slug)
    company_data&.dig(:id)
  end

  # Get complete company data from LinkedIn URL or identifier
  def get_company_full_data(linkedin_url_or_identifier)
    # Check if it's a URL or direct identifier
    if linkedin_url_or_identifier.to_s.include?('linkedin.com')
      company_identifier = extract_company_id_from_url(linkedin_url_or_identifier)
    else
      company_identifier = linkedin_url_or_identifier
    end

    return nil unless company_identifier

    get_company_data(company_identifier)
  end

  # Core method to get company data using the linkedin-api Python library
  def get_company_data(company_identifier)
    return nil unless company_identifier.present?

    Rails.logger.info "LinkedinCompanyExtractor: Fetching data for company: #{company_identifier}"

    begin
      result = execute_python_script(company_identifier)
      
      if result[:success]
        Rails.logger.info "LinkedinCompanyExtractor: Successfully retrieved data for #{company_identifier}"
        parse_company_data(result[:data])
      else
        Rails.logger.error "LinkedinCompanyExtractor: Failed to retrieve data for #{company_identifier}: #{result[:error]}"
        handle_api_error(result[:error])
        nil
      end
    rescue StandardError => e
      Rails.logger.error "LinkedinCompanyExtractor: Exception while fetching #{company_identifier}: #{e.message}"
      raise
    end
  end

  private

  def validate_credentials!
    if li_at_cookie.present?
      Rails.logger.info "LinkedinCompanyExtractor: Using cookie authentication"
      return
    end

    if linkedin_email.present? && linkedin_password.present?
      Rails.logger.info "LinkedinCompanyExtractor: Using username/password authentication"
      return
    end

    raise AuthenticationError, "LinkedIn credentials not configured. Set LINKEDIN_EMAIL and LINKEDIN_PASSWORD or LINKEDIN_COOKIE_LI_AT environment variables."
  end

  def execute_python_script(company_identifier)
    script_path = create_python_script_if_needed
    
    # Prepare authentication arguments
    auth_args = if li_at_cookie.present?
      ['--cookie-li-at', li_at_cookie]
    else
      ['--email', linkedin_email, '--password', linkedin_password]
    end

    # Add optional JSESSIONID cookie
    if jsessionid_cookie.present?
      auth_args += ['--cookie-jsessionid', jsessionid_cookie]
    end

    # Build command
    python_executable = find_python_executable
    command = [
      python_executable,
      script_path,
      company_identifier,
      *auth_args
    ]

    Rails.logger.info "LinkedinCompanyExtractor: Executing Python script for #{company_identifier}"
    
    # Execute command and capture output
    result = execute_command(command)
    
    # Parse JSON response
    begin
      parsed_result = JSON.parse(result[:output], symbolize_names: true)
      {
        success: parsed_result[:success],
        data: parsed_result[:data],
        error: parsed_result[:error]
      }
    rescue JSON::ParserError => e
      Rails.logger.error "LinkedinCompanyExtractor: Failed to parse Python script output: #{e.message}"
      Rails.logger.error "LinkedinCompanyExtractor: Raw output: #{result[:output]}"
      {
        success: false,
        error: "Failed to parse script output: #{e.message}"
      }
    end
  end

  def execute_command(command)
    Rails.logger.debug "LinkedinCompanyExtractor: Executing command: #{command.join(' ').gsub(linkedin_password.to_s, '*****')}"
    
    output = ""
    error_output = ""
    
    # Use Open3 for better process control
    require 'open3'
    
    Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      
      # Read output with timeout
      output = stdout.read
      error_output = stderr.read
      
      exit_status = wait_thr.value.exitstatus
      
      Rails.logger.debug "LinkedinCompanyExtractor: Command exit status: #{exit_status}"
      
      if exit_status != 0
        Rails.logger.error "LinkedinCompanyExtractor: Command failed with error: #{error_output}"
        return { success: false, output: error_output, exit_status: exit_status }
      end
    end
    
    { success: true, output: output, exit_status: 0 }
  end

  def find_python_executable
    # Check for virtual environment first
    venv_python = Rails.root.join('venv', 'bin', 'python3')
    return venv_python.to_s if File.exist?(venv_python)
    
    # Check for system python3
    system_python = `which python3`.strip
    return system_python if system_python.present? && File.exist?(system_python)
    
    # Fallback to python
    'python3'
  end

  def create_python_script_if_needed
    script_path = Rails.root.join('lib', 'linkedin_company_data_extractor.py')
    
    unless File.exist?(script_path)
      Rails.logger.info "LinkedinCompanyExtractor: Creating Python script at #{script_path}"
      create_python_script(script_path)
    end
    
    script_path.to_s
  end

  def create_python_script(script_path)
    script_content = <<~PYTHON
      #!/usr/bin/env python3
      """
      LinkedIn Company Data Extractor Script
      Ruby-callable Python script for extracting LinkedIn company data
      """
      
      import sys
      import json
      import argparse
      import logging
      from typing import Dict, Any, Optional
      
      try:
          from linkedin_api import Linkedin
      except ImportError:
          print(json.dumps({
              "success": False,
              "error": "linkedin-api library not installed. Run: pip install linkedin-api"
          }))
          sys.exit(1)
      
      # Configure logging
      logging.basicConfig(level=logging.WARNING)
      logger = logging.getLogger(__name__)
      
      
      def authenticate_linkedin(email: str = None, password: str = None, 
                               li_at_cookie: str = None, jsessionid_cookie: str = None) -> Optional[Linkedin]:
          """Authenticate with LinkedIn using credentials or cookies"""
          try:
              if li_at_cookie:
                  logger.info("Authenticating with cookies")
                  cookies = {'li_at': li_at_cookie}
                  if jsessionid_cookie:
                      cookies['JSESSIONID'] = jsessionid_cookie
                  api = Linkedin(email or "", password or "", cookies=cookies)
              else:
                  logger.info(f"Authenticating with username/password")
                  api = Linkedin(email, password)
              
              return api
          except Exception as e:
              logger.error(f"Authentication failed: {str(e)}")
              return None
      
      
      def extract_company_id_from_entity_urn(entity_urn: str) -> Optional[str]:
          """Extract company ID from LinkedIn entity URN"""
          if not entity_urn:
              return None
          
          # Format: urn:li:fs_normalized_company:1035
          parts = entity_urn.split(':')
          if len(parts) >= 4:
              return parts[-1]
          return None
      
      
      def get_company_data(api: Linkedin, company_identifier: str) -> Dict[str, Any]:
          """Get company data from LinkedIn API"""
          try:
              logger.info(f"Fetching company data for: {company_identifier}")
              
              # Use the get_company method from linkedin_api
              company_data = api.get_company(company_identifier)
              
              if not company_data:
                  return {
                      "success": False,
                      "error": f"Company not found: {company_identifier}"
                  }
              
              # Extract company ID from entity URN
              entity_urn = company_data.get('entityUrn', '')
              extracted_id = extract_company_id_from_entity_urn(entity_urn)
              
              # Get industry information
              industry = None
              if company_data.get('companyIndustries'):
                  industry = company_data['companyIndustries'][0].get('localizedName')
              
              # Build standardized response
              result = {
                  "success": True,
                  "data": {
                      "id": extracted_id,
                      "name": company_data.get('name'),
                      "universal_name": company_data.get('universalName'),
                      "description": company_data.get('description'),
                      "website": company_data.get('companyPageUrl'),
                      "industry": industry,
                      "staff_count": company_data.get('staffCount'),
                      "follower_count": company_data.get('staffCount'),  # Using staff count as proxy
                      "headquarters": None,
                      "founded_year": None,
                      "company_type": None,
                      "specialties": company_data.get('specialities', []),
                      "logo_url": None,
                      "entity_urn": entity_urn,
                      "raw_data": company_data
                  }
              }
              
              # Extract headquarters information
              if company_data.get('headquarter'):
                  hq = company_data['headquarter']
                  result["data"]["headquarters"] = {
                      "city": hq.get('city'),
                      "country": hq.get('country'),
                      "geographic_area": hq.get('geographicArea'),
                      "postal_code": hq.get('postalCode'),
                      "line1": hq.get('line1'),
                      "line2": hq.get('line2')
                  }
              
              # Extract logo URL
              if company_data.get('logo', {}).get('image'):
                  artifacts = company_data['logo']['image'].get('com.linkedin.common.VectorImage', {}).get('artifacts', [])
                  if artifacts:
                      # Get the largest available logo
                      largest_logo = max(artifacts, key=lambda x: x.get('width', 0))
                      root_url = company_data['logo']['image']['com.linkedin.common.VectorImage'].get('rootUrl', '')
                      result["data"]["logo_url"] = root_url + largest_logo.get('fileIdentifyingUrlPathSegment', '')
              
              # Extract company type
              if company_data.get('companyType'):
                  result["data"]["company_type"] = company_data['companyType'].get('localizedName')
              
              logger.info(f"Successfully retrieved data for {company_identifier}")
              return result
              
          except Exception as e:
              logger.error(f"Failed to get company data: {str(e)}")
              return {
                  "success": False,
                  "error": f"Failed to retrieve company data: {str(e)}"
              }
      
      
      def main():
          """Main function to handle command line arguments"""
          parser = argparse.ArgumentParser(description='LinkedIn Company Data Extractor')
          parser.add_argument('company_identifier', help='LinkedIn company ID or slug')
          parser.add_argument('--email', help='LinkedIn email')
          parser.add_argument('--password', help='LinkedIn password')
          parser.add_argument('--cookie-li-at', help='LinkedIn li_at cookie')
          parser.add_argument('--cookie-jsessionid', help='LinkedIn JSESSIONID cookie')
          
          args = parser.parse_args()
          
          # Authenticate with LinkedIn
          api = authenticate_linkedin(
              email=args.email,
              password=args.password,
              li_at_cookie=args.cookie_li_at,
              jsessionid_cookie=args.cookie_jsessionid
          )
          
          if not api:
              print(json.dumps({
                  "success": False,
                  "error": "Failed to authenticate with LinkedIn"
              }))
              sys.exit(1)
          
          # Get company data
          result = get_company_data(api, args.company_identifier)
          
          # Output JSON result
          print(json.dumps(result))
          
          if not result["success"]:
              sys.exit(1)
      
      
      if __name__ == "__main__":
          main()
    PYTHON

    File.write(script_path, script_content)
    File.chmod(script_path, 0o755)
    
    Rails.logger.info "LinkedinCompanyExtractor: Created Python script"
  end

  def parse_company_data(raw_data)
    return nil unless raw_data.is_a?(Hash)

    {
      id: raw_data[:id],
      name: raw_data[:name],
      universal_name: raw_data[:universal_name],
      description: raw_data[:description],
      website: raw_data[:website],
      industry: raw_data[:industry],
      staff_count: raw_data[:staff_count],
      follower_count: raw_data[:follower_count],
      headquarters: raw_data[:headquarters],
      founded_year: raw_data[:founded_year],
      company_type: raw_data[:company_type],
      specialties: raw_data[:specialties] || [],
      logo_url: raw_data[:logo_url],
      entity_urn: raw_data[:entity_urn],
      extracted_at: Time.current
    }
  end

  def handle_api_error(error_message)
    case error_message.to_s.downcase
    when /rate limit/
      raise RateLimitError, "LinkedIn API rate limit exceeded: #{error_message}"
    when /not found/
      raise CompanyNotFoundError, "Company not found: #{error_message}"
    when /authentication/
      raise AuthenticationError, "LinkedIn authentication failed: #{error_message}"
    else
      Rails.logger.error "LinkedinCompanyExtractor: Unhandled API error: #{error_message}"
    end
  end
end