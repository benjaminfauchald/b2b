class BrregMigrationWorker
  include Sidekiq::Worker
  sidekiq_options queue: "brreg_migration", retry: 3

  def perform(organisasjonsnummer)
    br = Brreg.find_by(organisasjonsnummer: organisasjonsnummer)
    unless br
      Rails.logger.warn "Brreg record not found for organisasjonsnummer: #{organisasjonsnummer}"
      return
    end

    begin
      company = Company.find_or_initialize_by(registration_number: br.organisasjonsnummer)

      # Skip if the company already exists and hasn't changed
      if company.persisted? && !company_changed?(company, br)
        Rails.logger.info "Skipping update for company #{br.organisasjonsnummer} - no changes detected"
        return
      end

      update_company_attributes(company, br)

      if company.save!
        Rails.logger.info "Successfully #{company.persisted? ? 'updated' : 'created'} company: #{br.organisasjonsnummer}"
      end

    rescue ActiveRecord::RecordNotUnique => e
      # This should be rare since we're using find_or_initialize_by
      Rails.logger.error "Race condition: Company with registration number #{br.organisasjonsnummer} already exists: #{e.message}"
    rescue => e
      Rails.logger.error "Error processing Brreg organisasjonsnummer=#{organisasjonsnummer}: #{e.message}"
      raise e # Re-raise to trigger Sidekiq retry
    end
  end

  private

  def company_changed?(company, br)
    company.new_record? ||
      company.company_name != br.navn ||
      company.organization_form_description != br.organisasjonsform_beskrivelse
    # Add any other fields you want to check for changes
  end

  def update_company_attributes(company, br)
    company.assign_attributes(
      source_country: "NO",
      source_registry: "brreg",
      source_id: br.organisasjonsnummer.to_s,
      company_name: br.navn,
      organization_form_code: br.organisasjonsform_kode,
      organization_form_description: br.organisasjonsform_beskrivelse,
      primary_industry_code: br.naeringskode1_kode,
      primary_industry_description: br.naeringskode1_beskrivelse,
      website: br.hjemmeside,
      email: br.epostadresse,
      phone: br.telefon,
      mobile: br.mobil,
      postal_address: br.forretningsadresse_adresse,
      postal_city: br.forretningsadresse_poststed,
      postal_code: br.forretningsadresse_postnummer,
      postal_municipality: br.forretningsadresse_kommune,
      postal_country: br.forretningsadresse_land,
      postal_country_code: br.forretningsadresse_landkode,
      has_registered_employees: br.harregistrertantallansatte == "true",
      employee_count: br.antallansatte&.to_i,
      employee_registration_date_registry: parse_date(br.registreringsdatoantallansatteenhetsregisteret),
      employee_registration_date_nav: parse_date(br.registreringsdatoantallansattenavaaregisteret)
    )
  end

  def parse_date(date_str)
    Date.parse(date_str) rescue nil
  end
end
