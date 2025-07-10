# frozen_string_literal: true

require 'csv'

class PhantomBusterImportService
  # Define expected headers for Phantom Buster CSV format
  PHANTOM_BUSTER_HEADERS = %w[
    profileUrl fullName firstName lastName companyName title 
    companyId companyUrl regularCompanyUrl summary titleDescription
    industry companyLocation location durationInRole durationInCompany
    pastExperienceCompanyName pastExperienceCompanyUrl 
    pastExperienceCompanyTitle pastExperienceDate pastExperienceDuration
    connectionDegree profileImageUrl sharedConnectionsCount name vmid
    linkedInProfileUrl isPremium isOpenLink query timestamp defaultProfileUrl
  ].freeze
  
  # Minimum headers required to identify as Phantom Buster format
  REQUIRED_HEADERS = %w[profileUrl fullName companyName title linkedInProfileUrl].freeze
  
  # Field mapping from CSV columns to Person model attributes
  FIELD_MAPPING = {
    'profileUrl' => :profile_url,
    'fullName' => :name,
    'firstName' => :first_name,
    'lastName' => :last_name,
    'companyName' => :company_name,
    'title' => :title,
    'companyId' => :phantom_buster_company_id,
    'companyUrl' => :company_url,
    'regularCompanyUrl' => :regular_company_url,
    'summary' => :bio,
    'titleDescription' => :title_description,
    'industry' => :industry,
    'companyLocation' => :company_location,
    'location' => :location,
    'durationInRole' => :duration_in_role,
    'durationInCompany' => :duration_in_company,
    'pastExperienceCompanyName' => :past_experience_company_name,
    'pastExperienceCompanyUrl' => :past_experience_company_url,
    'pastExperienceCompanyTitle' => :past_experience_company_title,
    'pastExperienceDate' => :past_experience_date,
    'pastExperienceDuration' => :past_experience_duration,
    'connectionDegree' => :connection_degree,
    'profileImageUrl' => :profile_picture_url,
    'sharedConnectionsCount' => :shared_connections_count,
    'vmid' => :vmid,
    'linkedInProfileUrl' => :profile_url,
    'isPremium' => :is_premium,
    'isOpenLink' => :is_open_link,
    'query' => :query,
    'timestamp' => :phantom_buster_timestamp,
    'defaultProfileUrl' => :default_profile_url
  }.freeze
  
  attr_reader :file_path, :errors, :import_results
  
  def initialize(file_path)
    @file_path = file_path
    @errors = []
    @import_results = {
      total: 0,
      successful: 0,
      updated: 0,
      failed: 0,
      duplicates: 0,
      errors: []
    }
  end
  
  def import(options = {})
    import_tag = options[:import_tag] || "phantom_buster_#{Time.current.to_i}"
    duplicate_strategy = options[:duplicate_strategy] || :skip # :skip, :update, :create_new
    
    return false unless valid_file?
    
    CSV.foreach(file_path, headers: true, encoding: 'UTF-8') do |row|
      @import_results[:total] += 1
      
      begin
        process_row(row, import_tag, duplicate_strategy)
      rescue StandardError => e
        @import_results[:failed] += 1
        @import_results[:errors] << {
          row: @import_results[:total],
          error: e.message,
          data: row.to_h
        }
      end
    end
    
    true
  rescue CSV::MalformedCSVError => e
    @errors << "Invalid CSV format: #{e.message}"
    false
  end
  
  def detect_format
    return false unless File.exist?(file_path)
    
    headers = CSV.open(file_path, 'r', headers: true, encoding: 'UTF-8') { |csv| csv.first&.headers }
    return false unless headers
    
    # Check if required headers are present
    missing_headers = REQUIRED_HEADERS - headers
    missing_headers.empty?
  rescue StandardError => e
    @errors << "Error reading file: #{e.message}"
    false
  end
  
  def preview(limit = 5)
    return [] unless valid_file?
    
    rows = []
    CSV.foreach(file_path, headers: true, encoding: 'UTF-8').with_index do |row, index|
      break if index >= limit
      
      rows << map_row_to_person_attributes(row)
    end
    
    rows
  rescue StandardError => e
    @errors << "Error previewing file: #{e.message}"
    []
  end
  
  private
  
  def valid_file?
    unless File.exist?(file_path)
      @errors << "File not found: #{file_path}"
      return false
    end
    
    unless detect_format
      @errors << "File does not match Phantom Buster CSV format. Missing required headers: #{REQUIRED_HEADERS.join(', ')}"
      return false
    end
    
    true
  end
  
  def process_row(row, import_tag, duplicate_strategy)
    attributes = map_row_to_person_attributes(row)
    attributes[:import_tag] = import_tag
    attributes[:source] = 'phantom_buster'
    
    # Check for existing person by profile_url
    existing_person = find_existing_person(attributes)
    
    if existing_person
      case duplicate_strategy
      when :update
        existing_person.update!(attributes)
        @import_results[:updated] += 1
      when :create_new
        # Remove unique fields for new record
        attributes.delete(:profile_url)
        attributes.delete(:email) if attributes[:email].present?
        Person.create!(attributes)
        @import_results[:successful] += 1
      when :skip
        # Do nothing, count as duplicate
        @import_results[:duplicates] += 1
      end
    else
      Person.create!(attributes)
      @import_results[:successful] += 1
    end
  end
  
  def find_existing_person(attributes)
    # Try to find by profile_url first (most reliable)
    if attributes[:profile_url].present?
      # First try exact match
      person = Person.find_by(profile_url: attributes[:profile_url])
      return person if person
      
      # Try finding by normalized URL using SQL LIKE patterns for common variations
      # This is much more efficient than loading all records into memory
      normalized_url = attributes[:profile_url]
      
      # Try common LinkedIn URL variations in the database
      possible_variations = [
        normalized_url,
        normalized_url.sub('https://', 'http://'),
        normalized_url.sub('http://', 'https://'),
        normalized_url.gsub(/\/$/, ''), # Remove trailing slash
        "#{normalized_url.gsub(/\/$/, '')}/" # Add trailing slash
      ]
      
      possible_variations.each do |variation|
        person = Person.find_by(profile_url: variation)
        return person if person
      end
    end
    
    # Try vmid as secondary identifier
    if attributes[:vmid].present?
      person = Person.find_by(vmid: attributes[:vmid])
      return person if person
    end
    
    # Try email if present
    if attributes[:email].present?
      person = Person.find_by(email: attributes[:email])
      return person if person
    end
    
    nil
  end
  
  def map_row_to_person_attributes(row)
    attributes = {}
    
    FIELD_MAPPING.each do |csv_field, model_field|
      value = row[csv_field]
      next if value.nil? || value.strip.empty?
      
      # Special handling for different field types
      case model_field
      when :is_premium, :is_open_link
        # Convert string to boolean
        attributes[model_field] = parse_boolean(value)
      when :shared_connections_count
        # Convert to integer
        attributes[model_field] = value.to_i
      when :phantom_buster_timestamp
        # Parse timestamp
        attributes[model_field] = parse_timestamp(value)
      when :profile_url
        # Skip if this is linkedInProfileUrl - we'll handle it specially below
        next if csv_field == 'linkedInProfileUrl'
        # Normalize LinkedIn URLs
        normalized_url = normalize_linkedin_url(value)
        attributes[model_field] = normalized_url if normalized_url.present?
      else
        # String fields
        attributes[model_field] = value.strip
      end
    end
    
    # Use defaultProfileUrl for the profile_url if available, otherwise fall back to linkedInProfileUrl
    if row['defaultProfileUrl'].present? && !row['defaultProfileUrl'].strip.empty?
      normalized_url = normalize_linkedin_url(row['defaultProfileUrl'])
      attributes[:profile_url] = normalized_url if normalized_url.present?
    elsif row['linkedInProfileUrl'].present? && !row['linkedInProfileUrl'].strip.empty?
      normalized_url = normalize_linkedin_url(row['linkedInProfileUrl'])
      attributes[:profile_url] = normalized_url if normalized_url.present?
    end
    
    # Store the Sales Navigator URL in metadata since no dedicated field exists
    if row['profileUrl'].present? && !row['profileUrl'].strip.empty?
      # Store in profile_data metadata instead of a non-existent field
      attributes[:profile_data] = { sales_navigator_url: row['profileUrl'].strip }
    end
    
    # Extract first and last names if not provided
    if attributes[:name].present? && (attributes[:first_name].blank? || attributes[:last_name].blank?)
      first, last = extract_names(attributes[:name])
      attributes[:first_name] ||= first
      attributes[:last_name] ||= last
    end
    
    attributes
  end
  
  def parse_boolean(value)
    %w[true yes 1].include?(value.to_s.downcase)
  end
  
  def parse_timestamp(value)
    DateTime.parse(value)
  rescue StandardError
    nil
  end
  
  def normalize_linkedin_url(url)
    # Use the Person model's normalization method for consistency
    Person.normalize_linkedin_url(url)
  end
  
  def extract_names(full_name)
    return [nil, nil] if full_name.blank?
    
    parts = full_name.strip.split(/\s+/)
    
    case parts.length
    when 0
      [nil, nil]
    when 1
      [parts[0], nil]
    when 2
      [parts[0], parts[1]]
    else
      # Assume first part is first name, rest is last name
      [parts[0], parts[1..-1].join(' ')]
    end
  end
end