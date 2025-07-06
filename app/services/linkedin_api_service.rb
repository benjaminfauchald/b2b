# frozen_string_literal: true

# LinkedIn API Service
# Uses linkedin-api Python library instead of browser automation
# Much more reliable and faster than Ferrum-based scraping
class LinkedinApiService < ApplicationService
  attr_reader :linkedin_email, :linkedin_password
  
  def initialize
    super(service_name: "linkedin_api_service")
    @linkedin_email = ENV['LINKEDIN_EMAIL']
    @linkedin_password = ENV['LINKEDIN_PASSWORD']
    
    validate_credentials!
  end
  
  # Main method to search for profiles using Sales Navigator-style search
  def search_profiles(search_params = {})
    Rails.logger.info "LinkedinApiService: Searching for profiles with params: #{search_params}"
    
    begin
      result = execute_python_search(search_params)
      
      if result[:success]
        Rails.logger.info "LinkedinApiService: Successfully found #{result[:profiles].size} profiles"
        {
          success: true,
          profiles: result[:profiles],
          total_found: result[:profiles].size
        }
      else
        Rails.logger.error "LinkedinApiService: Search failed - #{result[:error]}"
        {
          success: false,
          error: result[:error],
          profiles: []
        }
      end
    rescue StandardError => e
      Rails.logger.error "LinkedinApiService: Exception during search - #{e.message}"
      Rails.logger.error "LinkedinApiService: #{e.backtrace.first(5).join("\n")}"
      
      {
        success: false,
        error: e.message,
        profiles: []
      }
    end
  end
  
  # Get a single profile by LinkedIn public identifier
  def get_profile(public_id)
    Rails.logger.info "LinkedinApiService: Getting profile for: #{public_id}"
    
    begin
      result = execute_python_profile_lookup(public_id)
      
      if result[:success]
        Rails.logger.info "LinkedinApiService: Successfully retrieved profile for #{public_id}"
        {
          success: true,
          profile: result[:profile]
        }
      else
        Rails.logger.error "LinkedinApiService: Profile lookup failed - #{result[:error]}"
        {
          success: false,
          error: result[:error]
        }
      end
    rescue StandardError => e
      Rails.logger.error "LinkedinApiService: Exception during profile lookup - #{e.message}"
      
      {
        success: false,
        error: e.message
      }
    end
  end
  
  private
  
  def validate_credentials!
    unless @linkedin_email.present? && @linkedin_password.present?
      raise "LinkedIn credentials not configured. Set LINKEDIN_EMAIL and LINKEDIN_PASSWORD environment variables."
    end
  end
  
  # Execute Python script to search for profiles
  def execute_python_search(search_params)
    script_path = Rails.root.join('app', 'scripts', 'linkedin_search.py')
    ensure_python_script_exists!
    
    # Prepare search parameters as JSON
    search_json = search_params.to_json
    
    # Execute Python script with parameters using virtual environment
    venv_python = Rails.root.join('venv', 'bin', 'python3')
    python_executable = File.exist?(venv_python) ? venv_python : 'python3'
    
    command = [
      python_executable,
      script_path.to_s,
      'search',
      @linkedin_email,
      @linkedin_password,
      search_json
    ].join(' ')
    
    Rails.logger.info "LinkedinApiService: Executing command: #{command.gsub(@linkedin_password, '*****')}"
    
    output = `#{command}`
    exit_status = $?.exitstatus
    
    Rails.logger.info "LinkedinApiService: Python script exit status: #{exit_status}"
    Rails.logger.info "LinkedinApiService: Python script output length: #{output.length} chars"
    
    if exit_status == 0
      begin
        result = JSON.parse(output, symbolize_names: true)
        {
          success: true,
          profiles: result[:profiles] || []
        }
      rescue JSON::ParserError => e
        Rails.logger.error "LinkedinApiService: Failed to parse Python output as JSON: #{e.message}"
        Rails.logger.error "LinkedinApiService: Raw output: #{output}"
        {
          success: false,
          error: "Failed to parse search results: #{e.message}"
        }
      end
    else
      Rails.logger.error "LinkedinApiService: Python script failed with output: #{output}"
      {
        success: false,
        error: "Python script execution failed: #{output}"
      }
    end
  end
  
  # Execute Python script to get a single profile
  def execute_python_profile_lookup(public_id)
    script_path = Rails.root.join('app', 'scripts', 'linkedin_search.py')
    ensure_python_script_exists!
    
    # Execute Python script for profile lookup using virtual environment
    venv_python = Rails.root.join('venv', 'bin', 'python3')
    python_executable = File.exist?(venv_python) ? venv_python : 'python3'
    
    command = [
      python_executable,
      script_path.to_s,
      'profile',
      @linkedin_email,
      @linkedin_password,
      public_id
    ].join(' ')
    
    Rails.logger.info "LinkedinApiService: Executing profile lookup: #{command.gsub(@linkedin_password, '*****')}"
    
    output = `#{command}`
    exit_status = $?.exitstatus
    
    if exit_status == 0
      begin
        result = JSON.parse(output, symbolize_names: true)
        {
          success: true,
          profile: result[:profile]
        }
      rescue JSON::ParserError => e
        Rails.logger.error "LinkedinApiService: Failed to parse profile output as JSON: #{e.message}"
        {
          success: false,
          error: "Failed to parse profile data: #{e.message}"
        }
      end
    else
      Rails.logger.error "LinkedinApiService: Profile lookup failed with output: #{output}"
      {
        success: false,
        error: "Profile lookup failed: #{output}"
      }
    end
  end
  
  def ensure_python_script_exists!
    script_path = Rails.root.join('app', 'scripts', 'linkedin_search.py')
    unless File.exist?(script_path)
      create_python_script!
    end
  end
  
  def create_python_script!
    scripts_dir = Rails.root.join('app', 'scripts')
    FileUtils.mkdir_p(scripts_dir) unless Dir.exist?(scripts_dir)
    
    script_path = scripts_dir.join('linkedin_search.py')
    
    python_script_content = <<~PYTHON
      #!/usr/bin/env python3
      """
      LinkedIn API Search Script
      Uses linkedin-api library to search for profiles and companies
      """
      
      import sys
      import json
      import logging
      from typing import Dict, List, Any, Optional
      
      try:
          from linkedin_api import Linkedin
      except ImportError:
          print(json.dumps({
              "success": False,
              "error": "linkedin-api library not installed. Run: pip install linkedin-api"
          }))
          sys.exit(1)
      
      # Set up logging to help with debugging
      logging.basicConfig(level=logging.INFO)
      logger = logging.getLogger(__name__)
      
      
      def authenticate_linkedin(email: str, password: str) -> Optional[Linkedin]:
          """Authenticate with LinkedIn using credentials"""
          try:
              logger.info(f"Authenticating with LinkedIn using email: {email[:4]}***")
              api = Linkedin(email, password)
              logger.info("Successfully authenticated with LinkedIn")
              return api
          except Exception as e:
              logger.error(f"LinkedIn authentication failed: {str(e)}")
              return None
      
      
      def search_people(api: Linkedin, search_params: Dict[str, Any]) -> List[Dict[str, Any]]:
          """Search for people using linkedin-api"""
          try:
              # Extract search parameters
              keywords = search_params.get('keywords', '')
              company = search_params.get('company', '')
              location = search_params.get('location', '')
              limit = search_params.get('limit', 25)
              
              logger.info(f"Searching people with keywords='{keywords}', company='{company}', location='{location}'")
              
              # Use linkedin-api search_people method
              # Note: linkedin-api uses different parameter names than Sales Navigator
              search_kwargs = {}
              
              if keywords:
                  search_kwargs['keywords'] = keywords
              if company:
                  search_kwargs['current_company'] = [company]
              if location:
                  search_kwargs['regions'] = [location]
              
              # Perform the search
              results = api.search_people(limit=limit, **search_kwargs)
              
              # Transform results to our expected format
              profiles = []
              for person in results:
                  profile = {
                      'name': person.get('firstName', '') + ' ' + person.get('lastName', ''),
                      'headline': person.get('headline', ''),
                      'location': person.get('locationName', ''),
                      'public_id': person.get('publicIdentifier', ''),
                      'profile_url': f"https://www.linkedin.com/in/{person.get('publicIdentifier', '')}/",
                      'industry': person.get('industry', ''),
                      'summary': person.get('summary', ''),
                      'current_company': '',
                      'current_position': '',
                      'connection_degree': person.get('distance', ''),
                      'scraped_at': None  # We'll set this in Ruby
                  }
                  
                  # Extract current company and position from experience
                  if 'experience' in person and person['experience']:
                      current_exp = person['experience'][0]  # Most recent experience
                      profile['current_company'] = current_exp.get('companyName', '')
                      profile['current_position'] = current_exp.get('title', '')
                  
                  profiles.append(profile)
              
              logger.info(f"Successfully found {len(profiles)} profiles")
              return profiles
              
          except Exception as e:
              logger.error(f"People search failed: {str(e)}")
              raise
      
      
      def get_profile_details(api: Linkedin, public_id: str) -> Dict[str, Any]:
          """Get detailed profile information"""
          try:
              logger.info(f"Getting profile details for: {public_id}")
              
              profile_data = api.get_profile(public_id)
              
              # Transform to our expected format
              profile = {
                  'name': profile_data.get('firstName', '') + ' ' + profile_data.get('lastName', ''),
                  'headline': profile_data.get('headline', ''),
                  'location': profile_data.get('locationName', ''),
                  'public_id': public_id,
                  'profile_url': f"https://www.linkedin.com/in/{public_id}/",
                  'industry': profile_data.get('industryName', ''),
                  'summary': profile_data.get('summary', ''),
                  'current_company': '',
                  'current_position': '',
                  'experience': profile_data.get('experience', []),
                  'education': profile_data.get('education', []),
                  'skills': profile_data.get('skills', []),
                  'scraped_at': None  # We'll set this in Ruby
              }
              
              # Extract current company and position
              if profile_data.get('experience'):
                  current_exp = profile_data['experience'][0]
                  profile['current_company'] = current_exp.get('companyName', '')
                  profile['current_position'] = current_exp.get('title', '')
              
              logger.info(f"Successfully retrieved profile for {public_id}")
              return profile
              
          except Exception as e:
              logger.error(f"Profile lookup failed for {public_id}: {str(e)}")
              raise
      
      
      def main():
          """Main function to handle command line arguments"""
          if len(sys.argv) < 4:
              print(json.dumps({
                  "success": False,
                  "error": "Usage: python linkedin_search.py <command> <email> <password> [params]"
              }))
              sys.exit(1)
          
          command = sys.argv[1]
          email = sys.argv[2]
          password = sys.argv[3]
          
          # Authenticate with LinkedIn
          api = authenticate_linkedin(email, password)
          if not api:
              print(json.dumps({
                  "success": False,
                  "error": "Failed to authenticate with LinkedIn"
              }))
              sys.exit(1)
          
          try:
              if command == 'search':
                  if len(sys.argv) < 5:
                      print(json.dumps({
                          "success": False,
                          "error": "Search command requires search parameters as JSON"
                      }))
                      sys.exit(1)
                  
                  search_params = json.loads(sys.argv[4])
                  profiles = search_people(api, search_params)
                  
                  print(json.dumps({
                      "success": True,
                      "profiles": profiles
                  }))
                  
              elif command == 'profile':
                  if len(sys.argv) < 5:
                      print(json.dumps({
                          "success": False,
                          "error": "Profile command requires public_id parameter"
                      }))
                      sys.exit(1)
                  
                  public_id = sys.argv[4]
                  profile = get_profile_details(api, public_id)
                  
                  print(json.dumps({
                      "success": True,
                      "profile": profile
                  }))
                  
              else:
                  print(json.dumps({
                      "success": False,
                      "error": f"Unknown command: {command}"
                  }))
                  sys.exit(1)
                  
          except Exception as e:
              print(json.dumps({
                  "success": False,
                  "error": str(e)
              }))
              sys.exit(1)
      
      
      if __name__ == "__main__":
          main()
    PYTHON
    
    File.write(script_path, python_script_content)
    File.chmod(script_path.to_s, 0o755) # Make executable
    
    Rails.logger.info "LinkedinApiService: Created Python script at #{script_path}"
  end
end