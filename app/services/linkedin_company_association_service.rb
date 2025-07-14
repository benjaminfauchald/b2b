class LinkedinCompanyAssociationService < ApplicationService
  def initialize(batch_size: 500, **options)
    super(service_name: "linkedin_company_association", action: "associate_people", **options)
    @batch_size = batch_size
  end

  def perform
    return error_result("Service is disabled") unless service_active?
    
    # Use service configuration as auditable record for system-level operations
    config = ServiceConfiguration.find_by(service_name: service_name)
    
    audit_service_operation(config) do |audit_log|
      # Get UNIQUE LinkedIn company IDs from people needing association
      unique_linkedin_ids = Person.needing_company_association
                                  .where.not(linkedin_company_id: [nil, ''])
                                  .distinct
                                  .pluck(:linkedin_company_id)
      
      audit_log.add_metadata(
        unique_linkedin_ids_found: unique_linkedin_ids.count,
        total_people_needing_association: Person.needing_company_association.count,
        api_calls_needed: unique_linkedin_ids.count
      )
      
      # Limit API calls per day (configurable)
      max_api_calls = config&.settings&.dig("max_daily_api_calls") || 100
      unique_linkedin_ids = unique_linkedin_ids.first(max_api_calls)
      
      processed_ids = 0
      successful_associations = 0
      error_count = 0
      total_people_associated = 0
      
      unique_linkedin_ids.each do |linkedin_company_id|
        begin
          result = process_unique_linkedin_id(linkedin_company_id)
          
          if result[:success]
            successful_associations += 1
            total_people_associated += result[:people_count]
            audit_log.add_metadata("linkedin_id_#{linkedin_company_id}", {
              success: true,
              company_found: result[:company_name],
              people_associated: result[:people_count]
            })
          else
            error_count += 1
            audit_log.add_metadata("linkedin_id_#{linkedin_company_id}", {
              success: false,
              error: result[:error]
            })
          end
          
          processed_ids += 1
        rescue StandardError => e
          Rails.logger.error "Error processing LinkedIn ID #{linkedin_company_id}: #{e.message}"
          error_count += 1
          processed_ids += 1
        end
      end
      
      audit_log.add_metadata(
        processed_linkedin_ids: processed_ids,
        successful_linkedin_ids: successful_associations,
        total_people_associated: total_people_associated,
        error_count: error_count,
        success_rate: processed_ids > 0 ? (successful_associations.to_f / processed_ids * 100).round(2) : 0
      )
      
      success_result({
        processed: processed_ids,
        successful: successful_associations,
        errors: error_count,
        people_associated: total_people_associated
      })
    end
  end

  def call(person:)
    return error_result("Service is disabled") unless service_active?
    
    audit_service_operation do |audit_log|
      result = associate_person_with_company(person)
      
      audit_log.add_metadata(
        person_id: person.id,
        linkedin_company_id: person.linkedin_company_id,
        association_successful: result[:success]
      )
      
      if result[:success]
        audit_log.add_metadata(company_id: result[:company].id)
        success_result(result)
      else
        audit_log.add_metadata(error: result[:error])
        error_result(result[:error])
      end
    end
  end

  # Method for import processing - returns company without saving person
  def find_company_for_person(person)
    # First try LinkedIn company ID
    if person.linkedin_company_id.present?
      company = resolver.resolve(person.linkedin_company_id)
      return { success: true, company: company } if company
    end
    
    # If no LinkedIn company ID or resolution failed, try LinkedIn slug from query
    if person.query.present? && person.query.include?('linkedin.com/company/')
      linkedin_slug = person.query.match(/linkedin\.com\/company\/([^\/\?]+)/)[1] rescue nil
      
      if linkedin_slug.present?
        company = Company.find_by(linkedin_slug: linkedin_slug)
        
        if company
          return { success: true, company: company }
        else
          return { success: false, error: "Company not found for LinkedIn slug: #{linkedin_slug}" }
        end
      end
    end
    
    return { success: false, error: "No LinkedIn company ID or company slug found" }
  rescue StandardError => e
    { success: false, error: "Association failed: #{e.message}" }
  end

  # Method for individual person processing 
  def associate_person_with_company(person)
    # First try LinkedIn company ID
    if person.linkedin_company_id.present?
      company = resolver.resolve(person.linkedin_company_id)
      
      if company
        person.update!(company: company)
        return { success: true, company: company }
      end
    end
    
    # If no LinkedIn company ID or resolution failed, try LinkedIn slug from query
    if person.query.present? && person.query.include?('linkedin.com/company/')
      linkedin_slug = person.query.match(/linkedin\.com\/company\/([^\/\?]+)/)[1] rescue nil
      
      if linkedin_slug.present?
        company = Company.find_by(linkedin_slug: linkedin_slug)
        
        if company
          person.update!(company: company)
          return { success: true, company: company }
        else
          return { success: false, error: "Company not found for LinkedIn slug: #{linkedin_slug}" }
        end
      end
    end
    
    return { success: false, error: "No LinkedIn company ID or company slug found" }
  rescue StandardError => e
    { success: false, error: "Association failed: #{e.message}" }
  end

  def resolver
    @resolver ||= LinkedinCompanyResolver.new
  end

  private

  def process_unique_linkedin_id(linkedin_company_id)
    # Step 1: Convert LinkedIn ID to slug using API call
    slug = LinkedinCompanyDataService.id_to_slug(linkedin_company_id)
    
    return { success: false, error: "Could not convert LinkedIn ID to slug" } unless slug.present?
    
    # Step 2: Find company by slug
    company = Company.find_by(linkedin_slug: slug)
    
    return { success: false, error: "No company found with slug: #{slug}" } unless company
    
    # Step 3: Update ALL people with this LinkedIn company ID
    people_to_update = Person.needing_company_association.where(linkedin_company_id: linkedin_company_id)
    people_count = people_to_update.count
    
    return { success: false, error: "No people found with LinkedIn ID: #{linkedin_company_id}" } if people_count == 0
    
    # Step 4: Batch update all people
    people_to_update.update_all(company_id: company.id)
    
    # Step 5: Create lookup entry for future efficiency
    create_lookup_entry(linkedin_company_id, company, slug)
    
    {
      success: true,
      company_name: company.company_name,
      people_count: people_count,
      slug: slug
    }
  rescue StandardError => e
    { success: false, error: "Processing failed: #{e.message}" }
  end

  def create_lookup_entry(linkedin_company_id, company, slug)
    LinkedinCompanyLookup.find_or_create_by(linkedin_company_id: linkedin_company_id) do |lookup|
      lookup.company = company
      lookup.linkedin_slug = slug
      lookup.confidence_score = 100
      lookup.last_verified_at = Time.current
    end
  rescue StandardError => e
    Rails.logger.warn "Could not create lookup entry for LinkedIn ID #{linkedin_company_id}: #{e.message}"
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