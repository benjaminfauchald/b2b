# frozen_string_literal: true

require_relative '../../lib/linkedin_company_extractor'

# LinkedIn Company Data Service
# Extracts company information from LinkedIn using company IDs or slugs
# Follows the ApplicationService pattern and SCT compliance
class LinkedinCompanyDataService < ApplicationService
  # Service errors
  class ServiceError < StandardError; end
  class CompanyNotFoundError < ServiceError; end
  class AuthenticationError < ServiceError; end
  class RateLimitError < ServiceError; end

  attr_reader :company_identifier, :extractor

  def initialize(company_identifier: nil, linkedin_url: nil, **options)
    @company_identifier = company_identifier
    @linkedin_url = linkedin_url
    super(service_name: "linkedin_company_data", action: "extract", **options)
    
    validate_input!
    initialize_extractor
  end

  def perform
    return error_result("Service is disabled") unless service_active?

    audit_service_operation do |audit_log|
      Rails.logger.info "LinkedinCompanyDataService: Starting extraction for #{identifier_description}"
      
      begin
        # Extract company identifier from URL if provided
        if @linkedin_url.present?
          @company_identifier = @extractor.extract_company_id_from_url(@linkedin_url)
          unless @company_identifier
            audit_log.add_metadata(error: "invalid_url", url: @linkedin_url)
            return error_result("Invalid LinkedIn URL format")
          end
        end

        # Get company data
        company_data = @extractor.get_company_data(@company_identifier)
        
        if company_data.nil?
          audit_log.add_metadata(error: "company_not_found", identifier: @company_identifier)
          return error_result("Company not found")
        end

        # Add success metadata
        audit_log.add_metadata(
          company_id: company_data[:id],
          company_name: company_data[:name],
          universal_name: company_data[:universal_name],
          identifier_type: @extractor.numeric_id?(@company_identifier) ? "numeric_id" : "slug",
          data_freshness: "fresh"
        )

        Rails.logger.info "LinkedinCompanyDataService: Successfully extracted data for #{company_data[:name]}"
        success_result(company_data)

      rescue LinkedinCompanyExtractor::CompanyNotFoundError => e
        audit_log.add_metadata(error: "company_not_found", message: e.message)
        error_result("Company not found: #{e.message}")
      rescue LinkedinCompanyExtractor::AuthenticationError => e
        audit_log.add_metadata(error: "authentication_failed", message: e.message)
        error_result("Authentication failed: #{e.message}")
      rescue LinkedinCompanyExtractor::RateLimitError => e
        audit_log.add_metadata(error: "rate_limited", message: e.message)
        error_result("Rate limit exceeded: #{e.message}")
      rescue StandardError => e
        audit_log.add_metadata(error: "unexpected_error", message: e.message, backtrace: e.backtrace.first(5))
        Rails.logger.error "LinkedinCompanyDataService: Unexpected error: #{e.message}"
        error_result("Unexpected error: #{e.message}")
      end
    end
  end

  # Convenience methods for specific use cases
  def self.extract_from_url(linkedin_url)
    new(linkedin_url: linkedin_url).call
  end

  def self.extract_from_id(company_id)
    new(company_identifier: company_id).call
  end

  def self.extract_from_slug(company_slug)
    new(company_identifier: company_slug).call
  end

  # Get company name only
  def self.get_company_name(linkedin_url_or_id)
    result = new(company_identifier: linkedin_url_or_id).call
    result[:success] ? result[:data][:name] : nil
  end

  # Convert slug to numeric ID
  def self.slug_to_id(company_slug)
    service = new(company_identifier: company_slug)
    service.extractor.get_company_id_from_slug(company_slug)
  end

  # Convert numeric ID to slug
  def self.id_to_slug(company_id)
    result = extract_from_id(company_id)
    result[:success] ? result[:data][:universal_name] : nil
  end

  private

  def validate_input!
    unless @company_identifier.present? || @linkedin_url.present?
      raise ArgumentError, "Either company_identifier or linkedin_url must be provided"
    end
  end

  def initialize_extractor
    @extractor = LinkedinCompanyExtractor.new(
      linkedin_email: ENV['LINKEDIN_EMAIL'],
      linkedin_password: ENV['LINKEDIN_PASSWORD'],
      li_at_cookie: ENV['LINKEDIN_COOKIE_LI_AT'],
      jsessionid_cookie: ENV['LINKEDIN_COOKIE_JSESSIONID']
    )
  rescue LinkedinCompanyExtractor::AuthenticationError => e
    raise AuthenticationError, "LinkedIn authentication setup failed: #{e.message}"
  end

  def identifier_description
    if @linkedin_url.present?
      "URL: #{@linkedin_url}"
    else
      type = @extractor.numeric_id?(@company_identifier) ? "ID" : "slug"
      "#{type}: #{@company_identifier}"
    end
  end

  # SCT compliance methods
  def service_active?
    return true unless configuration.present?
    configuration.active?
  end

  def success_result(data)
    {
      success: true,
      data: data,
      extracted_at: Time.current,
      service: service_name
    }
  end

  def error_result(message)
    {
      success: false,
      error: message,
      extracted_at: Time.current,
      service: service_name
    }
  end

  # Service configuration setup
  def self.ensure_configuration!
    config = ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_data") do |c|
      c.active = true
      c.configuration_data = {
        rate_limit_per_hour: 100,
        timeout_seconds: 30,
        retry_attempts: 3,
        cache_duration_hours: 24
      }
      c.description = "LinkedIn Company Data Extraction Service"
    end

    Rails.logger.info "LinkedinCompanyDataService: Configuration #{config.persisted? ? 'found' : 'created'}"
    config
  end
end