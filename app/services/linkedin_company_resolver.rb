class LinkedinCompanyResolver
  def initialize
    @cache = Rails.cache
  end

  def resolve(linkedin_company_id)
    return nil unless linkedin_company_id.present?
    
    # Normalize the LinkedIn ID
    normalized_id = normalize_linkedin_id(linkedin_company_id)
    return nil unless normalized_id.present?
    
    # Strategy 1: Cache lookup
    cached_company = @cache.fetch(cache_key(normalized_id), expires_in: 1.hour) do
      resolve_from_strategies(normalized_id)
    end
    
    cached_company
  end

  private

  def normalize_linkedin_id(linkedin_company_id)
    # Clean up the LinkedIn ID - remove non-numeric characters
    cleaned_id = linkedin_company_id.to_s.gsub(/[^0-9]/, '')
    return nil if cleaned_id.blank?
    
    cleaned_id
  end

  def resolve_from_strategies(linkedin_company_id)
    # Strategy 1: Direct lookup table
    lookup = LinkedinCompanyLookup.find_by(linkedin_company_id: linkedin_company_id)
    if lookup&.company
      lookup.mark_verified! if lookup.stale?
      return lookup.company
    end

    # Strategy 2: Direct company match by linkedin_company_id
    company = Company.find_by(linkedin_company_id: linkedin_company_id)
    if company
      create_lookup_entry(linkedin_company_id, company, company.linkedin_slug)
      return company
    end

    # Strategy 3: Find companies that need LinkedIn ID population and check if they match
    # This is a fallback for companies that haven't been processed by LinkedinCompanyIdPopulationService
    companies_needing_ids = Company.where.not(linkedin_slug: nil).where(linkedin_company_id: nil).limit(10)
    companies_needing_ids.each do |company|
      converted_id = convert_slug_to_id(company.linkedin_slug)
      if converted_id == linkedin_company_id
        # Update the company with the linkedin_company_id for future direct matching
        company.update!(linkedin_company_id: converted_id)
        create_lookup_entry(linkedin_company_id, company, company.linkedin_slug)
        return company
      end
    end

    # Strategy 4: Fallback matching (if enabled)
    if fallback_enabled?
      company = fallback_company_matching(linkedin_company_id)
      if company
        create_lookup_entry(linkedin_company_id, company, company.linkedin_slug, confidence: 75)
        return company
      end
    end

    nil
  end

  def convert_slug_to_id(linkedin_slug)
    # Use the existing LinkedinCompanyDataService to convert slug to ID
    LinkedinCompanyDataService.slug_to_id(linkedin_slug)
  rescue StandardError => e
    Rails.logger.warn "Failed to convert LinkedIn slug #{linkedin_slug} to ID: #{e.message}"
    nil
  end

  def fallback_company_matching(linkedin_company_id)
    # Fallback strategy: try to find company by partial URL matching
    # This is a less reliable method, so we use lower confidence
    
    # Look for companies with linkedin_ai_url containing the ID
    companies_with_linkedin_data = Company.where(
      "(linkedin_url LIKE ? OR linkedin_ai_url LIKE ?)",
      "%#{linkedin_company_id}%",
      "%#{linkedin_company_id}%"
    )
    
    # Return first match if found
    companies_with_linkedin_data.first
  end

  def create_lookup_entry(linkedin_company_id, company, slug, confidence: 95)
    LinkedinCompanyLookup.find_or_create_by(linkedin_company_id: linkedin_company_id) do |lookup|
      lookup.company = company
      lookup.linkedin_slug = slug
      lookup.confidence_score = confidence
      lookup.last_verified_at = Time.current
    end
  rescue StandardError => e
    Rails.logger.warn "Could not create lookup entry for LinkedIn ID #{linkedin_company_id}: #{e.message}"
  end

  def cache_key(linkedin_company_id)
    "linkedin_company_resolver:#{linkedin_company_id}"
  end

  def fallback_enabled?
    config = ServiceConfiguration.find_by(service_name: "linkedin_company_association")
    config&.settings&.dig("enable_fallback_matching") == true
  end
end