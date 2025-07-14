class LinkedinCompanyIdPopulationService < ApplicationService
  def initialize(batch_size: 50, **options)
    super(service_name: "linkedin_company_id_population", action: "populate_ids", **options)
    @batch_size = batch_size
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    
    # Use service configuration as auditable record for system-level operations
    config = ServiceConfiguration.find_by(service_name: service_name)
    
    audit_service_operation(config) do |audit_log|
      companies_needing_ids = Company.where.not(linkedin_slug: nil).where(linkedin_company_id: nil)
      
      audit_log.add_metadata(
        companies_found: companies_needing_ids.count,
        batch_size: @batch_size
      )
      
      processed_count = 0
      success_count = 0
      error_count = 0
      
      companies_needing_ids.find_in_batches(batch_size: @batch_size) do |batch|
        batch.each do |company|
          begin
            # Convert slug to LinkedIn company ID
            linkedin_id = convert_slug_to_linkedin_id(company)
            
            if linkedin_id.present?
              company.update!(linkedin_company_id: linkedin_id)
              success_count += 1
              
              # Update or create lookup entry
              update_lookup_entry(company, linkedin_id)
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

  def convert_slug_to_linkedin_id(company)
    return nil unless company.linkedin_slug.present?
    
    # Use the LinkedinCompanyDataService to convert slug to ID
    LinkedinCompanyDataService.slug_to_id(company.linkedin_slug)
  rescue StandardError => e
    Rails.logger.warn "Failed to convert slug '#{company.linkedin_slug}' to LinkedIn ID for company #{company.id}: #{e.message}"
    nil
  end

  def update_lookup_entry(company, linkedin_id)
    return unless linkedin_id.present?
    
    LinkedinCompanyLookup.find_or_create_by(
      linkedin_company_id: linkedin_id
    ) do |lookup|
      lookup.company = company
      lookup.linkedin_slug = company.linkedin_slug
      lookup.confidence_score = 100  # High confidence for direct conversion
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