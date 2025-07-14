class LinkedinCompanySlugService < ApplicationService
  def initialize(batch_size: 100, **options)
    super(service_name: "linkedin_company_slug_population", action: "populate_slugs", **options)
    @batch_size = batch_size
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    
    # Use service configuration as auditable record for system-level operations
    config = ServiceConfiguration.find_by(service_name: service_name)
    
    audit_service_operation(config) do |audit_log|
      companies_needing_slugs = Company.needs_linkedin_slug_population
      
      audit_log.add_metadata(
        companies_found: companies_needing_slugs.count,
        batch_size: @batch_size
      )
      
      processed_count = 0
      success_count = 0
      error_count = 0
      
      companies_needing_slugs.find_in_batches(batch_size: @batch_size) do |batch|
        batch.each do |company|
          begin
            slug = extract_slug_from_company(company)
            
            if slug.present?
              # Handle duplicate slug constraint
              if Company.exists?(linkedin_slug: slug)
                Rails.logger.warn "Skipping company #{company.id} - slug '#{slug}' already exists"
                error_count += 1
              else
                company.update!(linkedin_slug: slug)
                success_count += 1
                
                # Update or create lookup entry
                update_lookup_entry(company, slug)
              end
            else
              error_count += 1
            end
            
            processed_count += 1
          rescue StandardError => e
            Rails.logger.error "Error processing company #{company.id}: #{e.message}"
            error_count += 1
            processed_count += 1
          end
        end
      end
      
      audit_log.add_metadata(
        processed_count: processed_count,
        success_count: success_count,
        error_count: error_count,
        success_rate: processed_count > 0 ? (success_count.to_f / processed_count * 100).round(2) : 0
      )
      
      success_result({
        processed: processed_count,
        successful: success_count,
        errors: error_count
      })
    end
  end

  private

  def extract_slug_from_company(company)
    # Priority: manual linkedin_url over AI-discovered linkedin_ai_url
    url = company.linkedin_url.presence || company.linkedin_ai_url.presence
    
    return nil unless url.present?
    
    extract_slug_from_url(url)
  end

  def extract_slug_from_url(url)
    # Extract slug from URLs like:
    # https://no.linkedin.com/company/betonmast → betonmast
    # https://www.linkedin.com/company/betonmast → betonmast
    # https://linkedin.com/company/betonmast-as → betonmast-as
    return nil unless url.present?
    
    # Normalize URL and extract slug
    normalized_url = url.strip.downcase
    
    # Match LinkedIn company URL patterns
    match = normalized_url.match(%r{linkedin\.com/company/([^/?&#]+)})
    return match[1] if match
    
    # Try alternative patterns
    match = normalized_url.match(%r{linkedin\.com/in/company/([^/?&#]+)})
    return match[1] if match
    
    nil
  end

  def update_lookup_entry(company, slug)
    return unless company.linkedin_company_id.present?
    
    LinkedinCompanyLookup.find_or_create_by(
      linkedin_company_id: company.linkedin_company_id
    ) do |lookup|
      lookup.company = company
      lookup.linkedin_slug = slug
      lookup.confidence_score = 100  # High confidence for direct extraction
      lookup.last_verified_at = Time.current
    end
  rescue StandardError => e
    Rails.logger.warn "Could not update lookup entry for company #{company.id}: #{e.message}"
  end

  def service_active?
    config = ServiceConfiguration.find_by(service_name: service_name)
    config&.active?
  end

  def success_result(data)
    { success: true, data: data }
  end

  def error_result(message)
    { success: false, error: message }
  end
end