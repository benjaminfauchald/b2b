# frozen_string_literal: true

require "public_suffix"

class CompanyDomainService
  attr_reader :company, :website_url

  def initialize(company, website_url)
    @company = company
    @website_url = website_url
  end

  def execute
    # Only return success with nil for truly nil/unset values
    return ServiceResult.success(domain: nil) if website_url.nil?

    # Normalize and validate the domain
    domain_name = normalize_domain(website_url)

    # Check if normalization resulted in empty string
    if domain_name.blank?
      return ServiceResult.error("Invalid domain format: empty domain")
    end

    unless valid_domain?(domain_name)
      return ServiceResult.error("Invalid domain format: #{domain_name}")
    end

    # Find or create the domain record
    domain = find_or_create_domain(domain_name)

    # Queue domain tests if needed
    queue_domain_tests(domain) if domain.needs_testing?

    ServiceResult.success(domain: domain)
  rescue StandardError => e
    ServiceResult.error("Failed to process domain: #{e.message}")
  end

  private

  def normalize_domain(url)
    # Remove protocol and www
    normalized = url.to_s.strip.downcase
    normalized = normalized.sub(%r{^https?://}, "")
    normalized = normalized.sub(/^www\./, "")
    # Remove path and query string
    normalized = normalized.split("/").first || normalized
    normalized = normalized.split("?").first || normalized
    # Remove port
    normalized.split(":").first || normalized
  end

  def valid_domain?(domain_name)
    return false if domain_name.blank?

    # Check for consecutive dots
    return false if domain_name.include?("..")

    begin
      # Use public_suffix gem for validation
      parsed = PublicSuffix.parse(domain_name)
      # Ensure it has at least a domain and TLD
      parsed.domain.present? && parsed.tld.present?
    rescue PublicSuffix::Error => e
      Rails.logger.error "Domain validation failed: #{e.message}"
      false
    end
  end

  def find_or_create_domain(domain_name)
    # Use a transaction to handle race conditions
    Domain.transaction do
      # First try to find existing domain for this company
      domain = company.domain

      if domain.present?
        # Update existing domain if it changed
        if domain.domain != domain_name
          domain.update!(domain: domain_name)
          # Reset test results for new domain
          domain.update!(dns: nil, mx: nil, www: nil, a_record_ip: nil, mx_error: nil)
        end
      else
        # Check if domain exists without company association
        existing_domain = Domain.find_by(domain: domain_name, company_id: nil)

        if existing_domain
          # Associate existing domain with company
          existing_domain.update!(company: company)
          domain = existing_domain
        else
          # Create new domain
          domain = Domain.create!(
            domain: domain_name,
            company: company
          )
        end
      end

      domain
    end
  end

  def queue_domain_tests(domain)
    # Queue DNS test which will cascade to other tests
    if ServiceConfiguration.active?("domain_testing")
      DomainDnsTestingWorker.perform_async(domain.id)

      # Log the queueing action
      ServiceAuditLog.create!(
        auditable: domain,
        service_name: "domain_testing",
        operation_type: "queue_from_company_update",
        status: "pending",
        table_name: domain.class.table_name,
        record_id: domain.id.to_s,
        columns_affected: [ "dns" ],
        metadata: {
          action: "queued_from_company_website_update",
          company_id: company.id,
          triggered_by: "company_domain_service"
        }
      )
    end
  end
end
