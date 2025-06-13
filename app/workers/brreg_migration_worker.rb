class BrregMigrationWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'brreg_migration', retry: 3

  def perform(organisasjonsnummer)
    br = Brreg.find_by(organisasjonsnummer: organisasjonsnummer)
    return unless br

    company_attrs = {
      source_country: 'NO',
      source_registry: 'brreg',
      source_id: br.organisasjonsnummer,
      registration_number: br.organisasjonsnummer,
      company_name: br.navn,
      organization_form_code: br.organisasjonsform_kode,
      organization_form_description: br.organisasjonsform_beskrivelse,
      primary_industry_code: br.naeringskode1_kode,
      primary_industry_description: br.naeringskode1_beskrivelse,
      secondary_industry_code: br.naeringskode2_kode,
      secondary_industry_description: br.naeringskode2_beskrivelse,
      tertiary_industry_code: br.naeringskode3_kode,
      tertiary_industry_description: br.naeringskode3_beskrivelse,
      business_description: br.aktivitet,
      employee_count: br.antallansatte,
      website: br.hjemmeside,
      email: br.epostadresse,
      phone: br.telefon,
      mobile: br.mobil,
      business_address: br.forretningsadresse_adresse,
      business_city: br.forretningsadresse_poststed,
      business_postal_code: br.forretningsadresse_postnummer,
      business_municipality: br.forretningsadresse_kommune,
      business_country: br.forretningsadresse_land,
      operating_revenue: br.driftsinntekter,
      operating_costs: br.driftskostnad,
      ordinary_result: br.ordinaertresultat,
      annual_result: br.aarsresultat,
      vat_registered: br.registrertimvaregisteret,
      vat_registration_date: br.registreringsdatomerverdiavgiftsregisteret,
      voluntary_vat_registered: br.frivilligmvaregistrertbeskrivelser,
      voluntary_vat_registration_date: br.registreringsdatofrivilligmerverdiavgiftsregisteret,
      registration_date: br.stiftelsesdato,
      bankruptcy: br.konkurs,
      bankruptcy_date: br.konkursdato,
      under_liquidation: br.underavvikling,
      liquidation_date: br.underavviklingdato,
      linkedin_url: br.linked_in,
      linkedin_ai_url: br.linked_in_ai,
      linkedin_alternatives: br.linked_in_alternatives,
      http_error: br.http_error,
      source_raw_data: br.brreg_result_raw
    }

    company = Company.find_or_initialize_by(registration_number: br.organisasjonsnummer)
    company.assign_attributes(company_attrs)
    company.save!
  rescue => e
    Rails.logger.error "Error processing Brreg organisasjonsnummer=#{organisasjonsnummer}: #{e.message}"
    raise e # This will trigger Sidekiq's retry mechanism
  end
end 