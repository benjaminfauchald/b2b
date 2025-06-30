# frozen_string_literal: true

require "csv"
require "smarter_csv"
require "ostruct"

class DomainImportService < ApplicationService
  REQUIRED_COLUMNS = %w[domain].freeze
  OPTIONAL_COLUMNS = %w[dns www mx].freeze
  MAX_FILE_SIZE = 50.megabytes
  VALID_MIME_TYPES = %w[text/csv application/csv text/plain].freeze

  def initialize(file:, user:, **options)
    @file = file
    @user = user
    @result = DomainImportResult.new
    super(service_name: "domain_import", action: "import", **options)
  end

  def perform
    Rails.logger.info "🔍 IMPORT DEBUG: Starting perform method"

    return error_result("Service is disabled") unless service_active?
    return error_result("No file provided") unless @file.present?
    return error_result("No user provided") unless @user.present?

    Rails.logger.info "🔍 IMPORT DEBUG: About to start audit_service_operation"

    audit_service_operation(@user) do |audit_log|
      Rails.logger.info "🚀 Starting domain import for user #{@user.id}"
      Rails.logger.info "🔍 IMPORT DEBUG: File details - name: #{@file.original_filename}, size: #{@file.size}"

      begin
        Rails.logger.info "🔍 IMPORT DEBUG: About to validate file"
        validate_file!

        Rails.logger.info "🔍 IMPORT DEBUG: About to process CSV file"
        process_csv_file

        Rails.logger.info "🔍 IMPORT DEBUG: About to finalize result"
        @result.finalize!

        Rails.logger.info "🔍 IMPORT DEBUG: About to add audit metadata"
        audit_log.add_metadata(
          user_id: @user.id,
          filename: @file.original_filename,
          file_size: @file.size,
          domains_imported: @result.imported_domains.count,
          domains_failed: @result.failed_domains.count,
          domains_duplicated: @result.duplicate_domains.count
        )

        Rails.logger.info "🔍 IMPORT DEBUG: About to return result"
        
        # Return appropriate result based on whether the import was successful
        if @result.success?
          success_result("Domain import completed successfully",
                        imported: @result.imported_domains.count,
                        failed: @result.failed_domains.count,
                        duplicates: @result.duplicate_domains.count,
                        result: @result)
        else
          error_result("Domain import completed with errors",
                      imported: @result.imported_domains.count,
                      failed: @result.failed_domains.count,
                      duplicates: @result.duplicate_domains.count,
                      result: @result)
        end

      rescue StandardError => e
        Rails.logger.error "❌ Domain import failed: #{e.message}"
        Rails.logger.error "❌ Backtrace: #{e.backtrace.join("\n")}"
        @result.set_error_message(e.message)
        @result.finalize!

        audit_log.add_metadata(
          user_id: @user.id,
          filename: @file.original_filename,
          error: e.message
        )

        error_result("Domain import failed: #{e.message}", result: @result)
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ Service error: #{e.message}"
    Rails.logger.error "❌ Service error backtrace: #{e.backtrace.join("\n")}"
    error_result("Service error: #{e.message}")
  end

  private

  attr_reader :file, :user, :result

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "domain_import")
    return false unless config
    config.active?
  end

  def validate_file!
    raise ArgumentError, "No file provided" if file.blank?
    raise ArgumentError, "Please upload a CSV file" unless valid_file_type?
    raise ArgumentError, "File size exceeds maximum allowed (20MB)" if file.size > MAX_FILE_SIZE
  end

  def valid_file_type?
    return false unless file.respond_to?(:content_type)

    VALID_MIME_TYPES.include?(file.content_type) ||
      file.original_filename&.downcase&.ends_with?(".csv")
  end

  def process_csv_file
    Rails.logger.info "🔍 IMPORT DEBUG: Entering process_csv_file method"

    # Debug: Check file contents
    Rails.logger.info "\n=== CSV IMPORT DEBUG ==="
    Rails.logger.info "🔍 File path: #{file.path}"
    Rails.logger.info "🔍 File exists: #{File.exist?(file.path)}"
    Rails.logger.info "🔍 File size: #{File.size(file.path) rescue 'N/A'}"

    # Read first few lines for debugging
    begin
      Rails.logger.info "🔍 IMPORT DEBUG: About to read first 5 lines"
      lines = File.readlines(file.path).first(5)
      Rails.logger.info "🔍 First 5 lines of file:"
      lines.each_with_index { |line, i| Rails.logger.info "  Line #{i}: #{line.strip}" }
    rescue => e
      Rails.logger.error "🔍 Error reading file: #{e.message}"
      Rails.logger.error "🔍 Error backtrace: #{e.backtrace.join("\n")}"
    end

    Rails.logger.info "🔍 IMPORT DEBUG: About to read first line"
    # Check if file has headers or is headerless
    first_line = File.open(file.path, &:readline).strip rescue ""
    Rails.logger.info "🔍 IMPORT DEBUG: First line read: '#{first_line}'"

    # File has headers if it contains "domain" in first line
    # Otherwise assume it's headerless (just domain names)
    has_headers = first_line.downcase.include?("domain")
    Rails.logger.info "🔍 IMPORT DEBUG: Has headers: #{has_headers}"

    Rails.logger.info "🔍 Processing CSV - First line: #{first_line}, Has headers: #{has_headers}"

    # For single-column files (just domain names), process line by line
    if !has_headers && first_line && !first_line.include?(",")
      Rails.logger.info "🔍 Processing as single-column domain list"
      process_simple_domain_list
    elsif !has_headers && first_line && first_line.include?(",")
      Rails.logger.info "🔍 Processing as headerless CSV"
      process_headerless_csv
    else
      Rails.logger.info "🔍 Processing as standard CSV with headers: #{has_headers}"
      # Multi-column CSV with SmarterCSV
      process_standard_csv(has_headers)
    end

    Rails.logger.info "🔍 IMPORT DEBUG: Finished process_csv_file method"
  end

  def validate_csv_structure!
    Rails.logger.info "🔍 IMPORT DEBUG: Entering validate_csv_structure! method"

    # Read just the header to validate structure
    begin
      Rails.logger.info "🔍 IMPORT DEBUG: About to call SmarterCSV.process for validation"
      first_row = nil
      
      # Get just the first row to check headers
      SmarterCSV.process(file.path, { chunk_size: 1 }) do |chunk|
        Rails.logger.info "🔍 IMPORT DEBUG: Got chunk: #{chunk.inspect}"
        first_row = chunk.first if chunk && !chunk.empty?
        break # Only need the first chunk
      end
      
      Rails.logger.info "🔍 IMPORT DEBUG: first_row: #{first_row.inspect}"

      if first_row.nil? || !first_row.is_a?(Hash)
        Rails.logger.error "🔍 IMPORT DEBUG: first_row is nil or not a hash!"
        raise ArgumentError, "CSV file is empty or contains no data rows"
      end

      Rails.logger.info "🔍 IMPORT DEBUG: About to get keys from first_row"
      keys = first_row.keys
      Rails.logger.info "🔍 IMPORT DEBUG: keys: #{keys.inspect}"

      headers = keys&.map(&:to_s) || []
      Rails.logger.info "🔍 IMPORT DEBUG: headers: #{headers.inspect}"

      missing_columns = REQUIRED_COLUMNS - headers
      Rails.logger.info "🔍 IMPORT DEBUG: missing_columns: #{missing_columns.inspect}"

      if missing_columns.any?
        Rails.logger.error "🔍 IMPORT DEBUG: Missing required columns: #{missing_columns.join(', ')}"
        raise ArgumentError, "Missing required column#{missing_columns.size > 1 ? 's' : ''}: #{missing_columns.join(', ')}"
      end

      Rails.logger.info "🔍 IMPORT DEBUG: validate_csv_structure! completed successfully"
    rescue => e
      Rails.logger.error "🔍 IMPORT DEBUG: Exception in validate_csv_structure!: #{e.message}"
      Rails.logger.error "🔍 IMPORT DEBUG: Exception backtrace: #{e.backtrace.join("\n")}"
      raise ArgumentError, "Could not parse CSV structure: #{e.message}"
    end
  end

  def process_single_row(row_data, row_number)
    puts "=== PROCESSING SINGLE ROW ==="
    puts "Row data: #{row_data.inspect}"
    puts "Row number: #{row_number}"

    domain_name = row_data[:domain].to_s.strip
    puts "Domain name extracted: '#{domain_name}'"

    # Validate domain name
    if domain_name.blank?
      puts "Domain is blank, marking as failed"
      result.add_failed_domain(domain_name, row_number, [ "Domain can't be blank" ])
      return
    end

    # Clean domain name (remove trailing/leading dots and whitespace)
    cleaned_domain = domain_name.strip.chomp(".").strip
    puts "Cleaned domain name: '#{cleaned_domain}'"

    # Validate domain format using the cleaned domain
    unless valid_domain_format?(cleaned_domain)
      result.add_failed_domain(domain_name, row_number, [ "Domain format is invalid" ])
      return
    end

    # Prepare domain attributes with cleaned domain
    domain_attributes = {
      domain: cleaned_domain,
      dns: parse_boolean_value(row_data[:dns]),
      www: parse_boolean_value(row_data[:www]),
      mx: parse_boolean_value(row_data[:mx])
    }

    # Check if domain already exists
    if Domain.exists?(domain: cleaned_domain)
      puts "Domain already exists, marking as duplicate"
      result.add_duplicate_domain(domain_name, row_number)
      return
    end

    # Try to create the domain
    begin
      domain = Domain.create!(domain_attributes)
      result.add_imported_domain(domain, row_number)
    rescue ActiveRecord::RecordInvalid => e
      result.add_failed_domain(domain_name, row_number, e.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      # This shouldn't happen since we check exists? above, but just in case
      result.add_duplicate_domain(domain_name, row_number)
    end
  end

  def parse_boolean_value(value)
    return nil if value.blank?

    case value.to_s.downcase.strip
    when "true", "1", "yes", "y", "t"
      true
    when "false", "0", "no", "n", "f"
      false
    else
      nil
    end
  end

  def valid_domain_format?(domain_name)
    # Clean the domain name (remove trailing/leading dots and whitespace)
    cleaned_domain = domain_name.to_s.strip.chomp(".").strip

    # Basic validations
    return false if cleaned_domain.blank?
    return false if cleaned_domain.length > 253  # Maximum domain length
    return false if cleaned_domain.include?("..")  # No consecutive dots
    return false unless cleaned_domain.include?(".")  # Must have at least one dot
    return false if cleaned_domain.start_with?(".") || cleaned_domain.end_with?(".")  # No leading/trailing dots

    # Split into parts and validate each
    parts = cleaned_domain.split(".")
    return false if parts.any?(&:blank?)  # No empty parts
    return false if parts.length < 2  # Must have at least domain + TLD

    # Validate each part
    parts.each do |part|
      return false if part.length > 63  # Max label length
      return false unless part.match?(/\A[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\z/) || part.match?(/\A[a-zA-Z0-9]\z/)
    end

    # TLD validation - must be at least 2 characters and alphabetic
    tld = parts.last
    return false unless tld.match?(/\A[a-zA-Z]{2,}\z/)

    true
  end

  def process_simple_domain_list
    Rails.logger.info "🔍 IMPORT DEBUG: Entering process_simple_domain_list method"

    row_count = 0
    File.foreach(file.path).with_index do |line, index|
      Rails.logger.info "🔍 IMPORT DEBUG: Processing line #{index}: '#{line.strip}'"

      line = line.strip
      next if line.empty?

      # Skip lines that look like headers
      next if line.downcase == "domain" || line.downcase == "domains"

      row_count += 1
      row_number = index + 1

      # Create row data hash with just domain
      row_data = { domain: line }

      Rails.logger.info "🔍 Processing row #{row_number}: #{row_data.inspect}"

      begin
        process_single_row(row_data, row_number)
        Rails.logger.info "🔍 IMPORT DEBUG: Successfully processed row #{row_number}"
      rescue => e
        Rails.logger.error "🔍 IMPORT DEBUG: Error processing row #{row_number}: #{e.message}"
        Rails.logger.error "🔍 IMPORT DEBUG: Row processing backtrace: #{e.backtrace.join("\n")}"
        raise e
      end
    end

    Rails.logger.info "🔍 Total rows processed: #{row_count}"
  end

  def process_headerless_csv
    csv_options = {
      chunk_size: 100,
      headers_in_file: false,
      user_provided_headers: [ :domain, :dns, :www, :mx ],
      remove_empty_values: false,
      convert_values_to_numeric: false,
      remove_zero_values: false,
      remove_values_matching: nil,
      remove_empty_hashes: false
    }

    row_count = 0
    SmarterCSV.process(file.path, csv_options) do |chunk|
      puts "Processing headerless chunk with #{chunk.size} rows"

      chunk.each_with_index do |row_data, index|
        row_count += 1
        puts "Processing row #{row_count}: #{row_data.inspect}"
        process_single_row(row_data, row_count)
      end
    end

    puts "Total rows processed: #{row_count}"
  end

  def process_standard_csv(has_headers)
    Rails.logger.info "🔍 IMPORT DEBUG: Entering process_standard_csv method with has_headers: #{has_headers}"

    csv_options = {
      chunk_size: 100,
      headers_in_file: has_headers,
      user_provided_headers: has_headers ? nil : [ :domain ],
      remove_empty_values: false,
      convert_values_to_numeric: false,
      remove_zero_values: false,
      remove_values_matching: nil,
      remove_empty_hashes: false
    }

    begin
      Rails.logger.info "🔍 IMPORT DEBUG: About to validate CSV structure" if has_headers
      validate_csv_structure! if has_headers

      Rails.logger.info "🔍 Starting SmarterCSV.process with options: #{csv_options.inspect}"

      Rails.logger.info "🔍 About to process with SmarterCSV"
      Rails.logger.info "🔍 CSV options: #{csv_options.inspect}"

      row_count = 0
      Rails.logger.info "🔍 IMPORT DEBUG: About to call SmarterCSV.process"

      SmarterCSV.process(file.path, csv_options) do |chunk|
        Rails.logger.info "🔍 Processing chunk with #{chunk.size} rows"

        chunk.each_with_index do |row_data, index|
          row_count += 1
          Rails.logger.info "🔍 Processing row #{index}: #{row_data.inspect}"
          row_number = calculate_row_number(chunk, index)

          begin
            process_single_row(row_data, row_number)
          rescue => e
            Rails.logger.error "🔍 IMPORT DEBUG: Error in process_single_row: #{e.message}"
            Rails.logger.error "🔍 IMPORT DEBUG: process_single_row backtrace: #{e.backtrace.join("\n")}"
            raise e
          end
        end
      end

      Rails.logger.info "🔍 Total rows processed: #{row_count}"
    rescue CSV::MalformedCSVError => e
      Rails.logger.error "🔍 IMPORT DEBUG: CSV::MalformedCSVError: #{e.message}"
      result.add_csv_error("CSV parsing error: #{e.message}")
    rescue SmarterCSV::SmarterCSVException => e
      Rails.logger.error "🔍 IMPORT DEBUG: SmarterCSV::SmarterCSVException: #{e.message}"
      result.add_csv_error("CSV processing error: #{e.message}")
    rescue => e
      Rails.logger.error "🔍 IMPORT DEBUG: Other error in process_standard_csv: #{e.message}"
      Rails.logger.error "🔍 IMPORT DEBUG: process_standard_csv backtrace: #{e.backtrace.join("\n")}"
      raise e
    end
  end

  def calculate_row_number(chunk, index)
    # Simple calculation - just use the index + 2 for header row
    index + 2
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
