require "firecrawl"
require "ostruct"

class DomainWebContentExtractionService < ApplicationService
  attr_reader :domain, :batch_size, :force

  def initialize(domain: nil, batch_size: 100, force: false, **options)
    @domain = domain
    @batch_size = batch_size
    @force = force
    super(service_name: "domain_web_content_extraction", action: "extract_content", **options)
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    return error_result("Firecrawl API key not configured") unless firecrawl_api_key

    if domain
      extract_single_domain
    else
      extract_domains_in_batches(Domain.needing_web_content)
    end
  rescue StandardError => e
    error_result("Service error: #{e.message}")
  end

  # Legacy class methods for backward compatibility
  def self.extract_web_content(domain)
    new(domain: domain).send(:extract_single_domain)
  end

  def self.queue_all_domains
    domains = Domain.needing_web_content
    count = 0

    domains.find_each do |domain|
      DomainWebContentExtractionWorker.perform_async(domain.id)
      count += 1
    end

    count
  end

  def self.queue_batch_domains(limit = 100)
    domains = Domain.needing_web_content.limit(limit)
    count = 0

    domains.each do |domain|
      DomainWebContentExtractionWorker.perform_async(domain.id)
      count += 1
    end

    count
  end

  private

  def extract_single_domain
    return error_result("Domain does not have a valid A record") unless domain.www && domain.a_record_ip.present?

    # Skip if recently extracted (unless forced)
    unless force
      last_extraction = domain.service_audit_logs
                             .where(service_name: service_name, status: "success")
                             .where("completed_at > ?", 24.hours.ago)
                             .exists?

      if last_extraction && domain.web_content_data.present?
        return success_result("Web content recently extracted", skipped: true)
      end
    end

    # Create the audit log manually to handle both success and failure cases
    audit_log = ServiceAuditLog.create!(
      auditable: domain,
      service_name: service_name,
      operation_type: "process",
      status: :pending,
      table_name: domain.class.table_name,
      record_id: domain.id.to_s,
      columns_affected: [ "web_content_data" ],
      metadata: { "status" => "initialized" },
      started_at: Time.current
    )

    result = perform_web_content_extraction

    if result[:success]
      store_web_content_data(domain, result[:data])

      audit_log.mark_success!(
        {
          domain_name: domain.domain,
          url: build_url,
          content_length: result[:data]["content"]&.length || 0,
          extraction_success: true
        },
        [ "web_content_data" ]
      )

      success_result("Web content extracted successfully", result: result)
    else
      audit_log.mark_failed!(
        result[:error],
        {
          domain_name: domain.domain,
          url: build_url,
          error: result[:error],
          extraction_success: false
        },
        [ "web_content_data" ]
      )

      error_result(result[:error])
    end
  end

  def perform_web_content_extraction
    url = build_url

    # Configure API key for this request
    Firecrawl.api_key firecrawl_api_key

    # Scrape with markdown format
    response = Firecrawl.scrape(url, { formats: [ "markdown", "html", "links" ] })

    if response.success?
      validate_and_normalize_content(response)
    else
      error_msg = response.respond_to?(:error_description) ? response.error_description : "Extraction failed"
      { success: false, error: error_msg }
    end
  rescue StandardError => e
    { success: false, error: "Firecrawl extraction failed: #{e.message}" }
  end

  def validate_and_normalize_content(result)
    return { success: false, error: "Invalid content data" } unless result.respond_to?(:markdown)

    # Ensure we have at least markdown or html content
    content = result.markdown || result.html
    return { success: false, error: "No content found" } if content.blank?

    normalized_data = {
      "content" => content,
      "markdown" => result.markdown,
      "html" => result.html,
      "title" => result.metadata&.[]("title"),
      "description" => result.metadata&.[]("description"),
      "url" => result.metadata&.[]("url"),
      "links" => result.links,
      "metadata" => result.metadata&.to_h || {},
      "screenshot_url" => result.screenshot_url,
      "extracted_at" => Time.current.iso8601
    }

    { success: true, data: normalized_data }
  end

  def store_web_content_data(domain, content_data)
    domain.update_columns(web_content_data: content_data)
  end

  def build_url
    protocol = domain.domain.start_with?("http") ? "" : "https://"
    "#{protocol}#{domain.domain}"
  end

  def extract_domains_in_batches(domains)
    results = { processed: 0, successful: 0, failed: 0, skipped: 0, errors: 0 }

    domains.find_each(batch_size: batch_size) do |domain|
      begin
        # Skip domains without A records (this shouldn't happen as the scope filters them)
        unless domain.www && domain.a_record_ip.present?
          results[:skipped] += 1
          results[:processed] += 1
          next
        end

        # Create the audit log manually
        audit_log = ServiceAuditLog.create!(
          auditable: domain,
          service_name: service_name,
          operation_type: "process",
          status: :pending,
          table_name: domain.class.table_name,
          record_id: domain.id.to_s,
          columns_affected: [ "web_content_data" ],
          metadata: { "status" => "initialized" },
          started_at: Time.current
        )

        # Set @domain for the batch operation
        @domain = domain
        result = perform_web_content_extraction_for_domain(domain)

        if result[:success]
          store_web_content_data(domain, result[:data])

          audit_log.mark_success!(
            {
              domain_name: domain.domain,
              url: build_url_for_domain(domain),
              content_length: result[:data]["content"]&.length || 0,
              extraction_success: true
            },
            [ "web_content_data" ]
          )

          results[:successful] += 1
        else
          audit_log.mark_failed!(
            result[:error],
            {
              domain_name: domain.domain,
              url: build_url_for_domain(domain),
              error: result[:error],
              extraction_success: false
            },
            [ "web_content_data" ]
          )
          results[:failed] += 1
        end
        results[:processed] += 1
      rescue StandardError => e
        results[:errors] += 1
        Rails.logger.error "Error extracting web content for domain #{domain.domain}: #{e.message}"
      end
    end

    success_result("Batch web content extraction completed",
                  processed: results[:processed],
                  successful: results[:successful],
                  failed: results[:failed],
                  skipped: results[:skipped],
                  errors: results[:errors])
  end

  def perform_web_content_extraction_for_domain(domain)
    url = build_url_for_domain(domain)

    # Configure API key for this request
    Firecrawl.api_key firecrawl_api_key

    # Scrape with markdown format
    response = Firecrawl.scrape(url, { formats: [ "markdown", "html", "links" ] })

    if response.success?
      validate_and_normalize_content(response)
    else
      error_msg = response.respond_to?(:error_description) ? response.error_description : "Extraction failed"
      { success: false, error: error_msg }
    end
  rescue StandardError => e
    { success: false, error: "Firecrawl extraction failed: #{e.message}" }
  end

  def build_url_for_domain(domain)
    protocol = domain.domain.start_with?("http") ? "" : "https://"
    "#{protocol}#{domain.domain}"
  end

  def firecrawl_api_key
    ENV["FIRECRAWL_API_KEY"]
  end

  def service_active?
    config = ServiceConfiguration.find_by(service_name: service_name)
    return false unless config
    config.active?
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
