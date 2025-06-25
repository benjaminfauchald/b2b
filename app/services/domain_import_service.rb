# frozen_string_literal: true

require "csv"
require "smarter_csv"

class DomainImportService < ApplicationService
  REQUIRED_COLUMNS = %w[domain].freeze
  OPTIONAL_COLUMNS = %w[dns www mx].freeze
  MAX_FILE_SIZE = 10.megabytes
  VALID_MIME_TYPES = %w[text/csv application/csv text/plain].freeze

  def initialize(file:, user:)
    # Call parent initializer to set up ActiveModel attributes
    super(service_name: "domain_import", action: "import")

    @file = file
    @user = user
    @result = DomainImportResult.new
  end

  def perform
    puts "\n=== DOMAIN IMPORT SERVICE CALLED ==="
    puts "File: #{@file.inspect}"
    puts "User: #{@user.inspect}"

    begin
      puts "Calling validate_file!"
      validate_file!
      puts "validate_file! completed"

      puts "Calling process_csv_file"
      process_csv_file
      puts "process_csv_file completed"

      puts "Calling @result.finalize!"
      @result.finalize!
      puts "@result.finalize! completed"

      puts "Final result: #{@result.to_h.inspect}"

      @result
    rescue StandardError => e
      puts "ERROR in perform: #{e.class.name}: #{e.message}"
      puts "Backtrace:"
      puts e.backtrace.first(10).join("\n")

      @result.set_error_message(e.message)
      @result.finalize!
      @result
    end
  end

  private

  attr_reader :file, :user, :result

  def validate_file!
    raise ArgumentError, "No file provided" if file.blank?
    raise ArgumentError, "Please upload a CSV file" unless valid_file_type?
    raise ArgumentError, "File size exceeds maximum allowed (10MB)" if file.size > MAX_FILE_SIZE
  end

  def valid_file_type?
    return false unless file.respond_to?(:content_type)

    VALID_MIME_TYPES.include?(file.content_type) ||
      file.original_filename&.downcase&.ends_with?(".csv")
  end

  def process_csv_file
    # Debug: Check file contents
    puts "\n=== CSV IMPORT DEBUG ==="
    puts "File path: #{file.path}"
    puts "File exists: #{File.exist?(file.path)}"
    puts "File size: #{File.size(file.path) rescue 'N/A'}"

    # Read first few lines for debugging
    begin
      lines = File.readlines(file.path).first(5)
      puts "First 5 lines of file:"
      lines.each_with_index { |line, i| puts "  Line #{i}: #{line.strip}" }
    rescue => e
      puts "Error reading file: #{e.message}"
    end

    # Check if file has headers or is headerless
    first_line = File.open(file.path, &:readline).strip rescue ""
    # File has headers if it contains "domain" in first line
    # Otherwise assume it's headerless (just domain names)
    has_headers = first_line.downcase.include?("domain")

    puts "Processing CSV - First line: #{first_line}, Has headers: #{has_headers}"

    # For single-column files (just domain names), process line by line
    if !has_headers && first_line && !first_line.include?(",")
      puts "Processing as single-column domain list"

      row_count = 0
      File.foreach(file.path).with_index do |line, index|
        line = line.strip
        next if line.empty?

        row_count += 1
        row_number = index + 1

        # Create row data hash with just domain
        row_data = { domain: line }

        puts "Processing row #{row_number}: #{row_data.inspect}"
        process_single_row(row_data, row_number)
      end

      puts "Total rows processed: #{row_count}"
    else
      # Multi-column CSV with SmarterCSV
      csv_options = {
        chunk_size: 100,          # Process in chunks for memory efficiency
        headers_in_file: has_headers,
        user_provided_headers: has_headers ? nil : [ :domain ],  # If no headers, assume single column is domain
        key_mapping: {            # Normalize column names
          "Domain" => :domain,
          "DNS" => :dns,
          "WWW" => :www,
          "MX" => :mx
        },
        remove_empty_values: false,
        convert_values_to_numeric: false,
        remove_zero_values: false,
        remove_values_matching: nil,
        remove_empty_hashes: false
      }

      begin
        validate_csv_structure! if has_headers

        Rails.logger.info "Starting SmarterCSV.process with options: #{csv_options.inspect}"

        puts "About to process with SmarterCSV"
        puts "CSV options: #{csv_options.inspect}"

        row_count = 0
        SmarterCSV.process(file.path, csv_options) do |chunk|
          puts "Processing chunk with #{chunk.size} rows"

          chunk.each_with_index do |row_data, index|
            row_count += 1
            puts "Processing row #{index}: #{row_data.inspect}"
            row_number = calculate_row_number(chunk, index)
            process_single_row(row_data, row_number)
          end
        end

        puts "Total rows processed: #{row_count}"
      rescue CSV::MalformedCSVError => e
        result.add_csv_error("CSV parsing error: #{e.message}")
      rescue SmarterCSV::SmarterCSVException => e
        result.add_csv_error("CSV processing error: #{e.message}")
      end
    end
  end

  def validate_csv_structure!
    # Read just the header to validate structure
    first_chunk = SmarterCSV.process(file.path, { chunk_size: 1 })

    if first_chunk.empty?
      raise ArgumentError, "CSV file is empty or contains no data rows"
    end

    headers = first_chunk.first.keys.map(&:to_s)
    missing_columns = REQUIRED_COLUMNS - headers

    if missing_columns.any?
      raise ArgumentError, "Missing required column#{missing_columns.size > 1 ? 's' : ''}: #{missing_columns.join(', ')}"
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

    # Clean domain name (remove trailing dot if present)
    cleaned_domain = domain_name.chomp(".")
    puts "Cleaned domain name: '#{cleaned_domain}'"

    # Validate domain format
    unless valid_domain_format?(domain_name)
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
    # Remove trailing dot if present (valid in DNS but not needed in storage)
    cleaned_domain = domain_name.chomp(".")

    # Basic domain validation regex
    # Allows for subdomains, requires at least one dot, no consecutive dots
    domain_regex = /\A[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\z/

    return false if cleaned_domain.length > 253  # Maximum domain length
    return false if cleaned_domain.include?("..")  # No consecutive dots
    return false unless cleaned_domain.include?(".")  # Must have at least one dot

    domain_regex.match?(cleaned_domain)
  end

  def calculate_row_number(chunk, index)
    # Account for header row and previous chunks
    # This is an approximation since we don't track exact position
    SmarterCSV.process(file.path, { chunk_size: 1, headers_in_file: true }) do |first_chunk|
      return index + 2  # +1 for zero-based index, +1 for header row
    end
  end
end
