# frozen_string_literal: true

require "csv"
require "smarter_csv"
require "ostruct"

class PersonImportService < ApplicationService
  REQUIRED_COLUMNS = %w[email].freeze
  OPTIONAL_COLUMNS = %w[name first_name last_name title company_name location linkedin phone email_status zb_status].freeze
  MAX_FILE_SIZE = 200.megabytes # Support larger files for person imports
  VALID_MIME_TYPES = %w[text/csv application/csv].freeze

  def initialize(file: nil, user: nil, validate_emails: false, **options)
    @file = file
    @user = user
    @validate_emails = validate_emails
    @import_tag = generate_import_tag
    @result = PersonImportResult.new(import_tag: @import_tag)
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

    # Detect if file has headers by checking for common header terms
    header_indicators = [ "name", "email", "first", "last", "title", "company", "linkedin" ]
    has_headers = header_indicators.any? { |indicator| first_line.downcase.include?(indicator) }

    # Always process as standard CSV with detected headers
    process_standard_csv(has_headers)
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
      row_count = 0

      SmarterCSV.process(file.path, csv_options) do |chunk|
        chunk.each_with_index do |row_data, index|
          row_count += 1

          process_single_row(row_data, row_count)
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
      "zerobounce status": :zb_status
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

    # Extract and clean LinkedIn URL
    linkedin_url = clean_linkedin_url(row_data[:linkedin])

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

    # Set email verification status if provided
    if row_data[:email_status].present? || row_data[:zb_status].present?
      email_status = (row_data[:email_status] || row_data[:zb_status]).to_s.downcase
      person_attributes[:email_verification_status] = map_email_status(email_status)
      person_attributes[:email_verification_checked_at] = Time.current
    end

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
          # Trigger email validation if enabled
          trigger_email_validation(existing_person) if @validate_emails
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
        # Trigger email validation if enabled
        trigger_email_validation(person) if @validate_emails
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

  def clean_linkedin_url(url)
    return nil if url.blank?

    url = url.to_s.strip
    # Extract LinkedIn profile URL from various formats
    if url.include?("linkedin.com")
      # Clean up the URL
      url.gsub(/,.*$/, "") # Remove anything after comma
         .strip
    else
      nil
    end
  end

  def clean_phone_number(phone)
    return nil if phone.blank?

    # Basic phone cleaning - remove non-digits except + and spaces
    phone.to_s.gsub(/[^\d\+\s\-\(\)]/, "").strip
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
    person_by_linkedin = Person.find_by(profile_url: linkedin_url) if linkedin_url.present?

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
end
