# frozen_string_literal: true

require "smarter_csv"

class DomainImportService < ApplicationService
  REQUIRED_COLUMNS = %w[domain].freeze
  OPTIONAL_COLUMNS = %w[dns www mx].freeze
  MAX_FILE_SIZE = 10.megabytes
  VALID_MIME_TYPES = %w[text/csv application/csv text/plain].freeze

  def initialize(file:, user:)
    @file = file
    @user = user
    @result = DomainImportResult.new
  end

  def perform
    audit_service_operation("domain_import", operation_type: "import") do |audit_log|
      validate_file!
      process_csv_file
      @result.finalize!

      # Update audit log with results
      audit_log.update!(
        metadata: @result.to_h.slice(:imported_count, :failed_count, :total_count)
      )

      @result
    end
  rescue StandardError => e
    @result.set_error_message(e.message)
    @result.finalize!
    @result
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
    csv_options = {
      chunk_size: 100,          # Process in chunks for memory efficiency
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
      validate_csv_structure!

      SmarterCSV.process(file.path, csv_options) do |chunk|
        chunk.each_with_index do |row_data, index|
          row_number = calculate_row_number(chunk, index)
          process_single_row(row_data, row_number)
        end
      end
    rescue CSV::MalformedCSVError => e
      result.add_csv_error("CSV parsing error: #{e.message}")
    rescue SmarterCSV::SmarterCSVException => e
      result.add_csv_error("CSV processing error: #{e.message}")
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
    domain_name = row_data[:domain].to_s.strip

    # Validate domain name
    if domain_name.blank?
      result.add_failed_domain(domain_name, row_number, [ "Domain can't be blank" ])
      return
    end

    # Prepare domain attributes
    domain_attributes = {
      domain: domain_name,
      dns: parse_boolean_value(row_data[:dns]),
      www: parse_boolean_value(row_data[:www]),
      mx: parse_boolean_value(row_data[:mx])
    }

    # Validate domain format
    unless valid_domain_format?(domain_name)
      result.add_failed_domain(domain_name, row_number, [ "Domain format is invalid" ])
      return
    end

    # Try to create the domain
    begin
      domain = Domain.create!(domain_attributes)
      result.add_imported_domain(domain, row_number)
    rescue ActiveRecord::RecordInvalid => e
      result.add_failed_domain(domain_name, row_number, e.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      result.add_failed_domain(domain_name, row_number, [ "Domain has already been taken" ])
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
    # Basic domain validation regex
    # Allows for subdomains, requires at least one dot, no consecutive dots
    domain_regex = /\A[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\z/

    return false if domain_name.length > 253  # Maximum domain length
    return false if domain_name.include?("..")  # No consecutive dots
    return false unless domain_name.include?(".")  # Must have at least one dot

    domain_regex.match?(domain_name)
  end

  def calculate_row_number(chunk, index)
    # Account for header row and previous chunks
    # This is an approximation since we don't track exact position
    SmarterCSV.process(file.path, { chunk_size: 1, headers_in_file: true }) do |first_chunk|
      return index + 2  # +1 for zero-based index, +1 for header row
    end
  end
end
