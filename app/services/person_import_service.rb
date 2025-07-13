# frozen_string_literal: true

require "csv"
require "smarter_csv"
require "ostruct"
require "timeout"

class PersonImportService < ApplicationService
  REQUIRED_COLUMNS = %w[email].freeze
  OPTIONAL_COLUMNS = %w[name first_name last_name title company_name location linkedin phone email_status zb_status].freeze
  ZEROBOUNCE_COLUMNS = %w[
    zb_status zb_sub_status zb_account zb_domain zb_first_name zb_last_name zb_gender
    zb_free_email zb_mx_found zb_mx_record zb_smtp_provider zb_did_you_mean
    zb_last_known_activity zb_activity_data_count zb_activity_data_types
    zb_activity_data_channels zerobouncequalityscore
  ].freeze
  
  # Phantom Buster CSV format detection
  PHANTOM_BUSTER_REQUIRED_HEADERS = %w[profileUrl fullName companyName title linkedInProfileUrl].freeze
  PHANTOM_BUSTER_HEADERS = %w[
    profileUrl fullName firstName lastName companyName title 
    companyId companyUrl regularCompanyUrl summary titleDescription
    industry companyLocation location durationInRole durationInCompany
    pastExperienceCompanyName pastExperienceCompanyUrl 
    pastExperienceCompanyTitle pastExperienceDate pastExperienceDuration
    connectionDegree profileImageUrl sharedConnectionsCount name vmid
    linkedInProfileUrl isPremium isOpenLink query timestamp defaultProfileUrl
  ].freeze
  
  MAX_FILE_SIZE = 200.megabytes # Support larger files for person imports
  VALID_MIME_TYPES = %w[text/csv application/csv].freeze

  def initialize(file: nil, user: nil, validate_emails: false, **options)
    @file = file
    @user = user
    @validate_emails = validate_emails
    @import_tag = generate_import_tag
    @result = PersonImportResult.new(import_tag: @import_tag)
    Rails.logger.info "🔧 PersonImportService initialized with validate_emails: #{@validate_emails.inspect}" if @validate_emails
    super(service_name: "person_import", action: "import", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("No file provided") unless @file.present?
    return error_result("No user provided") unless @user.present?

    audit_service_operation(@user) do |audit_log|
      Rails.logger.info "🚀 Starting person import for user #{@user.id}"

      begin
        validate_file!
        process_csv_file
        @result.finalize!

        # Update final progress
        update_progress(@result.total_count, @result.total_count, "Import completed successfully!")

        audit_log.add_metadata(
          user_id: @user.id,
          filename: @file.original_filename,
          file_size: @file.size,
          import_tag: @import_tag,
          people_imported: @result.imported_people.count,
          people_updated: @result.updated_people.count,
          people_failed: @result.failed_people.count,
          people_duplicated: @result.duplicate_people.count
        )

        # Return appropriate result based on whether the import was successful
        if @result.success?
          success_result("Person import completed successfully",
                        imported: @result.imported_people.count,
                        updated: @result.updated_people.count,
                        failed: @result.failed_people.count,
                        duplicates: @result.duplicate_people.count,
                        result: @result)
        else
          error_result("Person import completed with errors",
                      imported: @result.imported_people.count,
                      updated: @result.updated_people.count,
                      failed: @result.failed_people.count,
                      duplicates: @result.duplicate_people.count,
                      result: @result)
        end

      rescue StandardError => e
        Rails.logger.error "❌ Person import failed: #{e.message}"
        Rails.logger.error "❌ Backtrace: #{e.backtrace.join("\n")}"
        @result.set_error_message(e.message)
        @result.finalize!

        audit_log.add_metadata(
          user_id: @user.id,
          filename: @file.original_filename,
          import_tag: @import_tag,
          error: e.message
        )

        error_result("Person import failed: #{e.message}", result: @result)
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ Service error: #{e.message}"
    Rails.logger.error "❌ Service error backtrace: #{e.backtrace.join("\n")}"
    error_result("Service error: #{e.message}")
  end

  attr_reader :import_tag

  private

  attr_reader :file, :user, :result

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "person_import")
    return false unless config
    config.active?
  end

  def validate_file!
    raise ArgumentError, "No file provided" if file.blank?
    raise ArgumentError, "Please upload a CSV file" unless valid_file_type?
    raise ArgumentError, "File size exceeds maximum allowed (200MB)" if file.size > MAX_FILE_SIZE
  end

  def valid_file_type?
    return false unless file.respond_to?(:content_type)

    VALID_MIME_TYPES.include?(file.content_type) ||
      file.original_filename&.downcase&.ends_with?(".csv")
  end

  def process_csv_file
    # Check if file has headers
    first_line = File.open(file.path, &:readline).strip rescue ""
    
    # Check if this is a Phantom Buster CSV
    if is_phantom_buster_csv?(first_line)
      Rails.logger.info "🚀 Detected Phantom Buster CSV format"
      process_phantom_buster_csv
    else
      # Detect if file has headers by checking for common header terms
      header_indicators = [ "name", "email", "first", "last", "title", "company", "linkedin" ]
      has_headers = header_indicators.any? { |indicator| first_line.downcase.include?(indicator) }

      # Always process as standard CSV with detected headers
      process_standard_csv(has_headers)
    end
  end
  
  def is_phantom_buster_csv?(first_line)
    # Parse CSV headers properly (handle quoted headers)
    headers = CSV.parse_line(first_line).map(&:strip).map(&:downcase)
    required_headers = PHANTOM_BUSTER_REQUIRED_HEADERS.map(&:downcase)
    missing_headers = required_headers - headers
    
    Rails.logger.info "🔍 Checking Phantom Buster format"
    Rails.logger.info "  Headers found: #{headers.inspect}"
    Rails.logger.info "  Required headers: #{required_headers.inspect}"
    Rails.logger.info "  Missing headers: #{missing_headers.inspect}"
    
    missing_headers.empty?
  end
  
  def process_phantom_buster_csv
    # Delegate to PhantomBusterImportService
    phantom_service = PhantomBusterImportService.new(file.path)
    
    unless phantom_service.detect_format
      result.add_csv_error("Invalid Phantom Buster CSV format")
      return
    end
    
    # Import using the Phantom Buster service
    import_result = phantom_service.import(
      import_tag: @import_tag,
      duplicate_strategy: :update
    )
    
    if import_result
      # Map results back to our result object
      phantom_results = phantom_service.import_results
      
      # Update our result with Phantom Buster import results
      result.merge_phantom_buster_results(phantom_results)
      
      # Handle email validation if enabled
      if @validate_emails && phantom_results[:successful] > 0
        # Find all successfully imported people and queue for validation
        people = Person.where(import_tag: @import_tag)
        people.each do |person|
          trigger_email_validation(person)
          result.track_email_verification(person, true)
        end
      end
    else
      result.add_csv_error("Phantom Buster import failed: #{phantom_service.errors.join(', ')}")
    end
  end

  def process_standard_csv(has_headers)
    csv_options = {
      chunk_size: 100,
      headers_in_file: has_headers,
      remove_empty_values: false,
      convert_values_to_numeric: false,
      remove_zero_values: false,
      remove_values_matching: nil,
      remove_empty_hashes: false
    }

    begin
      # Count total rows for progress calculation
      total_rows = count_csv_rows(has_headers)
      row_count = 0

      # Initialize progress tracking
      update_progress(0, total_rows, "Starting import...")

      SmarterCSV.process(file.path, csv_options) do |chunk|
        chunk.each_with_index do |row_data, index|
          row_count += 1

          process_single_row(row_data, row_count)

          # Progress tracking without artificial delay in production

          # Update progress every row for small imports, every 10 rows for larger ones
          update_frequency = total_rows <= 20 ? 1 : 10
          if row_count % update_frequency == 0 || row_count == total_rows
            progress_percent = (row_count.to_f / total_rows * 100).round(1)
            update_progress(row_count, total_rows, "Processing row #{row_count} of #{total_rows} (#{progress_percent}%)")
          end
        end
      end

    rescue CSV::MalformedCSVError => e
      result.add_csv_error("CSV parsing error: #{e.message}")
    rescue SmarterCSV::SmarterCSVException => e
      result.add_csv_error("CSV processing error: #{e.message}")
    rescue => e
      raise e
    end
  end

  def normalize_headers_mapping
    {
      # Name mappings
      name: :name,
      "full name": :name,
      fullname: :name,
      "first name": :first_name,
      firstname: :first_name,
      "last name": :last_name,
      lastname: :last_name,

      # Email mappings
      email: :email,
      "email address": :email,
      mail: :email,

      # Title mappings
      title: :title,
      position: :title,
      "job title": :title,
      role: :title,

      # Company mappings
      "company name": :company_name,
      company: :company_name,
      organization: :company_name,

      # Location mappings
      location: :location,
      city: :location,
      address: :location,

      # LinkedIn mappings
      linkedin: :linkedin,
      "linkedin url": :linkedin,
      "profile url": :linkedin,
      profile: :linkedin,

      # Phone mappings
      phone: :phone,
      "phone number": :phone,
      mobile: :phone,
      telephone: :phone,

      # Email status mappings
      "email status": :email_status,
      "zb status": :zb_status,
      "zerobounce status": :zb_status,

      # ZeroBounce field mappings
      "zb sub status": :zb_sub_status,
      "zb substatus": :zb_sub_status,
      "zerobounce sub status": :zb_sub_status,
      "zb account": :zb_account,
      "zerobounce account": :zb_account,
      "zb domain": :zb_domain,
      "zerobounce domain": :zb_domain,
      "zb first name": :zb_first_name,
      "zerobounce first name": :zb_first_name,
      "zb last name": :zb_last_name,
      "zerobounce last name": :zb_last_name,
      "zb gender": :zb_gender,
      "zerobounce gender": :zb_gender,
      "zb free email": :zb_free_email,
      "zerobounce free email": :zb_free_email,
      "zb mx found": :zb_mx_found,
      "zerobounce mx found": :zb_mx_found,
      "zb mx record": :zb_mx_record,
      "zerobounce mx record": :zb_mx_record,
      "zb smtp provider": :zb_smtp_provider,
      "zerobounce smtp provider": :zb_smtp_provider,
      "zb did you mean": :zb_did_you_mean,
      "zerobounce did you mean": :zb_did_you_mean,
      "zb last known activity": :zb_last_known_activity,
      "zerobounce last known activity": :zb_last_known_activity,
      "zb activity data count": :zb_activity_data_count,
      "zerobounce activity data count": :zb_activity_data_count,
      "zb activity data types": :zb_activity_data_types,
      "zerobounce activity data types": :zb_activity_data_types,
      "zb activity data channels": :zb_activity_data_channels,
      "zerobounce activity data channels": :zb_activity_data_channels,
      "zerobouncequalityscore": :zerobouncequalityscore,
      "zerobounce quality score": :zerobouncequalityscore,
      "zb quality score": :zerobouncequalityscore
    }
  end

  def process_single_row(row_data, row_number)
    # Extract and clean data
    email = row_data[:email]&.to_s&.strip&.downcase

    # Skip if no email
    if email.blank?
      result.add_failed_person(row_data, row_number, [ "Email can't be blank" ])
      return
    end

    # Validate email format
    unless valid_email_format?(email)
      result.add_failed_person(row_data, row_number, [ "Email format is invalid" ])
      return
    end

    # Build name from parts if needed
    name = row_data[:name]&.to_s&.strip
    if name.blank? && (row_data[:first_name].present? || row_data[:last_name].present?)
      name = "#{row_data[:first_name]&.to_s&.strip} #{row_data[:last_name]&.to_s&.strip}".strip
    end

    # Extract and normalize LinkedIn URL using Person model's method
    linkedin_url = Person.normalize_linkedin_url(row_data[:linkedin])

    # Prepare person attributes
    person_attributes = {
      name: name,
      email: email,
      title: row_data[:title]&.to_s&.strip,
      company_name: row_data[:company_name]&.to_s&.strip,
      location: row_data[:location]&.to_s&.strip,
      profile_url: linkedin_url,
      phone: clean_phone_number(row_data[:phone]),
      import_tag: @import_tag
    }

    # Add ZeroBounce fields if present
    map_zerobounce_fields(row_data, person_attributes)

    # Store external email validation data in metadata but DON'T set verification status
    # The system should perform its own verification instead of trusting external sources
    if row_data[:email_status].present? || row_data[:zb_status].present?
      external_status = (row_data[:email_status] || row_data[:zb_status]).to_s.downcase
      person_attributes[:email_verification_metadata] = {
        external_validation: {
          source: row_data[:email_status].present? ? "email_status" : "zb_status",
          original_status: external_status,
          mapped_status: map_email_status(external_status),
          imported_at: Time.current
        }
      }
    end

    # Always start with unverified status for imported emails
    person_attributes[:email_verification_status] = "unverified"

    # Associate with company if exists
    if person_attributes[:company_name].present?
      company = Company.find_by(company_name: person_attributes[:company_name])
      person_attributes[:company_id] = company.id if company
    end

    # Find existing person by email OR LinkedIn profile URL
    existing_person = find_existing_person(email, linkedin_url)

    if existing_person
      # Merge data - imported data overwrites existing data
      merged_attributes = merge_person_data(existing_person, person_attributes)

      if merged_attributes.any?
        begin
          existing_person.update!(merged_attributes)
          result.add_updated_person(existing_person, row_number, merged_attributes)
          # Trigger email validation if enabled and track stats
          if @validate_emails
            trigger_email_validation(existing_person)
            result.track_email_verification(existing_person, true)
          else
            result.track_email_verification(existing_person, false)
          end
        rescue ActiveRecord::RecordInvalid => e
          result.add_failed_person(row_data, row_number, e.record.errors.full_messages)
        end
      else
        result.add_duplicate_person(row_data, row_number)
      end
    else
      # Create new person
      begin
        person = Person.create!(person_attributes)
        result.add_imported_person(person, row_number)
        # Trigger email validation if enabled and track stats
        if @validate_emails
          trigger_email_validation(person)
          result.track_email_verification(person, true)
        else
          result.track_email_verification(person, false)
        end
      rescue ActiveRecord::RecordInvalid => e
        result.add_failed_person(row_data, row_number, e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotUnique
        # Handle race condition - try to find and update the person that was just created
        existing_person = find_existing_person(email, linkedin_url)
        if existing_person
          merged_attributes = merge_person_data(existing_person, person_attributes)
          if merged_attributes.any?
            existing_person.update!(merged_attributes)
            result.add_updated_person(existing_person, row_number, merged_attributes)
            # Trigger email validation if enabled and track stats
            if @validate_emails
              trigger_email_validation(existing_person)
              result.track_email_verification(existing_person, true)
            else
              result.track_email_verification(existing_person, false)
            end
          else
            result.add_duplicate_person(row_data, row_number)
          end
        else
          result.add_failed_person(row_data, row_number, [ "Unique constraint violation" ])
        end
      end
    end
  end

  def valid_email_format?(email)
    # Basic email validation
    email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
  end


  def clean_phone_number(phone)
    return nil if phone.blank?

    # Basic phone cleaning - remove non-digits except + and spaces
    phone.to_s.gsub(/[^\d\+\s\-\(\)]/, "").strip
  end

  def map_zerobounce_fields(row_data, person_attributes)
    zerobounce_mapping = {
      zb_status: :zerobounce_status,
      zb_sub_status: :zerobounce_sub_status,
      zb_account: :zerobounce_account,
      zb_domain: :zerobounce_domain,
      zb_first_name: :zerobounce_first_name,
      zb_last_name: :zerobounce_last_name,
      zb_gender: :zerobounce_gender,
      zb_free_email: :zerobounce_free_email,
      zb_mx_found: :zerobounce_mx_found,
      zb_mx_record: :zerobounce_mx_record,
      zb_smtp_provider: :zerobounce_smtp_provider,
      zb_did_you_mean: :zerobounce_did_you_mean,
      zb_last_known_activity: :zerobounce_last_known_activity,
      zb_activity_data_count: :zerobounce_activity_data_count,
      zb_activity_data_types: :zerobounce_activity_data_types,
      zb_activity_data_channels: :zerobounce_activity_data_channels,
      zerobouncequalityscore: :zerobounce_quality_score
    }

    zerobounce_data_present = false

    zerobounce_mapping.each do |csv_key, model_attr|
      next unless row_data[csv_key].present?

      value = row_data[csv_key]

      # Handle specific field type conversions
      case model_attr
      when :zerobounce_free_email, :zerobounce_mx_found
        # Convert to boolean
        person_attributes[model_attr] = %w[true yes 1].include?(value.to_s.downcase)
      when :zerobounce_activity_data_count
        # Convert to integer
        person_attributes[model_attr] = value.to_i if value.to_s.match?(/^\d+$/)
      when :zerobounce_quality_score
        # Convert to decimal
        person_attributes[model_attr] = value.to_f if value.to_s.match?(/^\d*\.?\d+$/)
      when :zerobounce_last_known_activity
        # Parse timestamp if it looks like a date
        begin
          person_attributes[model_attr] = Time.parse(value.to_s) if value.to_s.present?
        rescue ArgumentError
          # Skip invalid dates
        end
      else
        # String fields - clean and store
        person_attributes[model_attr] = value.to_s.strip
      end

      zerobounce_data_present = true
    end

    # Set imported timestamp if any ZeroBounce data was found
    person_attributes[:zerobounce_imported_at] = Time.current if zerobounce_data_present

    person_attributes
  end

  def map_email_status(status)
    case status
    when "valid", "catch-all", "unknown", "accept-all"
      "valid"
    when "invalid", "abuse", "do_not_mail", "spamtrap", "disposable"
      "invalid"
    else
      "unverified"
    end
  end

  def find_existing_person(email, linkedin_url)
    person_by_email = Person.find_by(email: email) if email.present?
    
    # Search for LinkedIn URL with normalization
    person_by_linkedin = nil
    if linkedin_url.present?
      # First try exact match
      person_by_linkedin = Person.find_by(profile_url: linkedin_url)
      
      # If not found, try to find any person whose normalized URL matches
      unless person_by_linkedin
        Person.where.not(profile_url: nil).find_each do |person|
          if Person.normalize_linkedin_url(person.profile_url) == linkedin_url
            person_by_linkedin = person
            break
          end
        end
      end
    end

    # If both exist and are different people, we need to merge them
    if person_by_email && person_by_linkedin && person_by_email.id != person_by_linkedin.id
      # Merge person_by_linkedin into person_by_email, then delete person_by_linkedin
      merge_duplicate_people(person_by_email, person_by_linkedin)
      return person_by_email
    end

    # Return the found person (email takes precedence)
    person_by_email || person_by_linkedin
  end

  def merge_duplicate_people(primary_person, duplicate_person)
    # Merge data from duplicate into primary, keeping non-blank values
    merge_attributes = {}

    duplicate_person.attributes.each do |key, value|
      next if %w[id created_at updated_at].include?(key)
      next if value.blank?

      # Only update if primary person doesn't have this data
      if primary_person[key].blank?
        merge_attributes[key] = value
      end
    end

    # Update primary person with merged data
    primary_person.update!(merge_attributes) if merge_attributes.any?

    # Transfer any associated records if needed (email_verification_attempts, etc.)
    duplicate_person.email_verification_attempts.update_all(person_id: primary_person.id)

    # Delete the duplicate person
    duplicate_person.destroy!
  rescue StandardError => e
    Rails.logger.error "Failed to merge duplicate people: #{e.message}"
    # Continue without merging if there's an error
  end

  def merge_person_data(existing_person, new_attributes)
    merged_attributes = {}

    new_attributes.each do |key, value|
      # Skip if new value is blank/nil
      next if value.blank?

      current_value = existing_person[key]

      # Always update with imported data (imported data takes precedence)
      if current_value != value
        merged_attributes[key] = value
      end
    end

    merged_attributes
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

  def generate_import_tag
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    user_prefix = @user&.email&.split("@")&.first || "unknown"
    "import_#{user_prefix}_#{timestamp}"
  end

  def trigger_email_validation(person)
    return unless person.email.present?
    return if person.email_verification_status == "valid"

    # Queue email validation asynchronously to avoid blocking import
    begin
      # Use hybrid verification service if available, fallback to local
      if defined?(LocalEmailVerifyWorker)
        LocalEmailVerifyWorker.perform_async(person.id)
        Rails.logger.info "✅ Email validation queued for person #{person.id} during import"
      else
        # Fallback to synchronous validation with timeout
        Timeout.timeout(10) do  # Increased timeout for hybrid service
          # Try hybrid service first, fallback to local
          verification_service = if ServiceConfiguration.find_by(service_name: "hybrid_email_verify")&.active?
                                  People::HybridEmailVerifyService.new(person: person)
          else
                                  People::LocalEmailVerifyService.new(person: person)
          end
          verification_service.perform
        end
        Rails.logger.info "✅ Email validation completed for person #{person.id} during import"
      end
    rescue Timeout::Error
      Rails.logger.warn "⏰ Email validation timed out for person #{person.id} during import - skipping"
    rescue StandardError => e
      Rails.logger.error "❌ Email validation failed for person #{person.id} during import: #{e.message}"
      # Don't fail the import if email validation fails
    end
  end

  def count_csv_rows(has_headers)
    line_count = 0
    File.foreach(file.path) { line_count += 1 }
    has_headers ? line_count - 1 : line_count
  rescue StandardError => e
    Rails.logger.warn "Failed to count CSV rows: #{e.message}"
    0 # Fallback to 0 if counting fails
  end

  def update_progress(current, total, message)
    return unless @user # Only track progress if we have a user

    progress_key = "person_import_progress_#{@user.id}"
    progress_data = {
      current: current,
      total: total,
      percent: total > 0 ? (current.to_f / total * 100).round(1) : 0,
      message: message,
      updated_at: Time.current.iso8601
    }

    # Store progress in Rails cache (Redis if available, memory otherwise)
    Rails.cache.write(progress_key, progress_data, expires_in: 10.minutes)
  rescue StandardError => e
    Rails.logger.warn "Failed to update import progress: #{e.message}"
  end
end
