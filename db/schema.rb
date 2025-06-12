# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_06_12_152542) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activity", id: :serial, force: :cascade do |t|
    t.text "activity", null: false
    t.integer "organisasjonsnummer", null: false
    t.text "parameters"
    t.text "description"
    t.datetime "created_at", precision: nil, default: -> { "now()" }
    t.datetime "updated_at", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "ended_at", precision: nil
  end

  create_table "brreg", id: :serial, force: :cascade do |t|
    t.integer "organisasjonsnummer"
    t.text "navn"
    t.text "organisasjonsform_kode"
    t.text "organisasjonsform_beskrivelse"
    t.decimal "naeringskode1_kode"
    t.text "naeringskode1_beskrivelse"
    t.decimal "naeringskode2_kode"
    t.text "naeringskode2_beskrivelse"
    t.text "naeringskode3_kode"
    t.text "naeringskode3_beskrivelse"
    t.decimal "hjelpeenhetskode_kode"
    t.text "hjelpeenhetskode_beskrivelse"
    t.text "harregistrertantallansatte"
    t.integer "antallansatte"
    t.text "registreringsdatoantallansatteenhetsregisteret"
    t.text "registreringsdatoantallansattenavaaregisteret"
    t.text "hjemmeside"
    t.text "epostadresse"
    t.text "telefon"
    t.text "mobil"
    t.text "postadresse_adresse"
    t.text "postadresse_poststed"
    t.integer "postadresse_postnummer"
    t.text "postadresse_kommune"
    t.integer "postadresse_kommunenummer"
    t.text "postadresse_land"
    t.text "postadresse_landkode"
    t.text "forretningsadresse_adresse"
    t.text "forretningsadresse_poststed"
    t.integer "forretningsadresse_postnummer"
    t.text "forretningsadresse_kommune"
    t.integer "forretningsadresse_kommunenummer"
    t.text "forretningsadresse_land"
    t.text "forretningsadresse_landkode"
    t.integer "institusjonellsektorkode_kode"
    t.text "institusjonellsektorkode_beskrivelse"
    t.integer "sisteinnsendteaarsregnskap"
    t.text "registreringsdatoenhetsregisteret"
    t.text "stiftelsesdato"
    t.text "registrertimvaregisteret"
    t.text "registreringsdatomerverdiavgiftsregisteret"
    t.text "registreringsdatomerverdiavgiftsregisteretenhetsregisteret"
    t.text "frivilligmvaregistrertbeskrivelser"
    t.text "registreringsdatofrivilligmerverdiavgiftsregisteret"
    t.text "registrertifrivillighetsregisteret"
    t.text "registreringsdatofrivillighetsregisteret"
    t.text "registrertiforetaksregisteret"
    t.text "registreringsdatoforetaksregisteret"
    t.text "registrertistiftelsesregisteret"
    t.text "registrertipartiregisteret"
    t.text "registreringsdatopartiregisteret"
    t.text "konkurs"
    t.text "konkursdato"
    t.text "underavvikling"
    t.text "underavviklingdato"
    t.text "undertvangsavviklingellertvangsopplosning"
    t.text "tvangsopplostpgamanglendedagliglederdato"
    t.text "tvangsopplostpgamanglenderevisordato"
    t.text "tvangsopplostpgamanglenderegnskapdato"
    t.text "tvangsopplostpgamangelfulltstyredato"
    t.text "tvangsavvikletpgamanglendeslettingdato"
    t.text "overordnetenhet"
    t.text "maalform"
    t.text "vedtektsdato"
    t.text "vedtektsfestetformaal"
    t.text "aktivitet"
    t.text "registreringsnummerihjemlandet"
    t.text "paategninger"
    t.bigint "ordinaertresultat"
    t.bigint "aarsresultat"
    t.bigint "driftsinntekter"
    t.bigint "driftskostnad"
    t.integer "http_error"
    t.text "http_error_message"
    t.text "description"
    t.text "industry"
    t.text "country"
    t.text "webpage"
    t.text "linked_in_ai"
    t.text "sps_match"
    t.text "sps_match_percentage"
    t.text "linked_in"
    t.text "linked_in_alt"
    t.jsonb "linked_in_alternatives"
    t.jsonb "brreg_result_raw"
    t.text "segment"
    t.boolean "linkedin_processed", default: false
    t.datetime "linkedin_last_processed_at", precision: nil
    t.integer "linkedin_employee_count", default: 0
    t.serial "brreg_id", null: false
    t.integer "linked_in_ai_confidence", comment: "AI confidence percentage (0-100) for LinkedIn URL accuracy"
    t.index ["linked_in_ai_confidence"], name: "idx_brreg_linkedin_confidence"
    t.index ["organisasjonsnummer"], name: "idx_brreg_organisasjonsnummer", unique: true
    t.check_constraint "linked_in_ai_confidence >= 0 AND linked_in_ai_confidence <= 100", name: "chk_linkedin_confidence"
    t.unique_constraint ["organisasjonsnummer"], name: "brreg_organisasjonsnummer_unique"
  end

  create_table "companies", id: :serial, force: :cascade do |t|
    t.string "source_country", limit: 2, null: false
    t.string "source_registry", limit: 20, null: false
    t.text "source_id", null: false
    t.text "registration_number", null: false
    t.text "company_name", null: false
    t.text "organization_form_code"
    t.text "organization_form_description"
    t.date "registration_date"
    t.date "deregistration_date"
    t.text "deregistration_reason"
    t.text "registration_country"
    t.text "primary_industry_code"
    t.text "primary_industry_description"
    t.text "secondary_industry_code"
    t.text "secondary_industry_description"
    t.text "tertiary_industry_code"
    t.text "tertiary_industry_description"
    t.text "auxiliary_unit_code"
    t.text "auxiliary_unit_description"
    t.text "business_description"
    t.text "segment"
    t.text "industry"
    t.boolean "has_registered_employees"
    t.integer "employee_count"
    t.date "employee_registration_date_registry"
    t.date "employee_registration_date_nav"
    t.integer "linkedin_employee_count"
    t.text "website"
    t.text "email"
    t.text "phone"
    t.text "mobile"
    t.text "postal_address"
    t.text "postal_city"
    t.text "postal_code"
    t.text "postal_municipality"
    t.text "postal_municipality_code"
    t.text "postal_country"
    t.text "postal_country_code"
    t.text "business_address"
    t.text "business_city"
    t.text "business_postal_code"
    t.text "business_municipality"
    t.text "business_municipality_code"
    t.text "business_country"
    t.text "business_country_code"
    t.integer "institutional_sector_code"
    t.text "institutional_sector_description"
    t.integer "last_submitted_annual_report"
    t.bigint "ordinary_result"
    t.bigint "annual_result"
    t.bigint "operating_revenue"
    t.bigint "operating_costs"
    t.boolean "vat_registered"
    t.date "vat_registration_date"
    t.date "vat_registration_date_entity_registry"
    t.boolean "voluntary_vat_registered"
    t.date "voluntary_vat_registration_date"
    t.boolean "nonprofit_registered"
    t.date "nonprofit_registration_date"
    t.boolean "enterprise_registered"
    t.date "enterprise_registration_date"
    t.boolean "foundation_registered"
    t.boolean "party_registered"
    t.date "party_registration_date"
    t.boolean "bankruptcy"
    t.date "bankruptcy_date"
    t.boolean "under_liquidation"
    t.date "liquidation_date"
    t.boolean "under_forced_liquidation"
    t.date "forced_dissolution_missing_ceo_date"
    t.date "forced_dissolution_missing_auditor_date"
    t.date "forced_dissolution_missing_accounts_date"
    t.date "forced_dissolution_missing_board_date"
    t.date "forced_liquidation_missing_deletion_date"
    t.boolean "ongoing_restructuring"
    t.text "parent_entity"
    t.date "foundation_date"
    t.text "language_form"
    t.date "statute_date"
    t.text "statutory_purpose"
    t.text "activity_description"
    t.text "home_country_registration_number"
    t.text "notes"
    t.integer "name_protection_expiry_number"
    t.text "linkedin_url"
    t.text "linkedin_ai_url"
    t.text "linkedin_alt_url"
    t.jsonb "linkedin_alternatives"
    t.boolean "linkedin_processed", default: false
    t.datetime "linkedin_last_processed_at", precision: nil
    t.integer "linkedin_ai_confidence"
    t.text "sps_match"
    t.text "sps_match_percentage"
    t.integer "http_error"
    t.text "http_error_message"
    t.jsonb "source_raw_data"
    t.integer "brreg_id"
    t.string "country", limit: 2
    t.text "description"
    t.datetime "created_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
  end

  create_table "domains", force: :cascade do |t|
    t.string "domain"
    t.boolean "www"
    t.boolean "mx"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "dns"
  end

  create_table "html_errors", id: :serial, force: :cascade do |t|
    t.text "domain", null: false
    t.text "error_message"
    t.text "method"
    t.integer "http_status"
    t.timestamptz "occurred_at", default: -> { "now()" }
  end

  create_table "linkedin_profiles", id: :integer, default: -> { "nextval('linkedin_leads_id_seq'::regclass)" }, force: :cascade do |t|
    t.string "name", limit: 255
    t.string "title", limit: 500
    t.string "company", limit: 255
    t.string "location", limit: 255
    t.text "profile_url"
    t.string "email", limit: 255
    t.string "phone", limit: 50
    t.string "connection_degree", limit: 20
    t.datetime "extracted_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.string "phantom_run_id", limit: 50
    t.integer "brreg_id"
    t.string "company_name", limit: 255
    t.integer "linkedin_seniority_level"
    t.boolean "is_executive_role", default: false
    t.integer "company_id"
    t.index ["brreg_id"], name: "idx_linkedin_leads_brreg_id"
    t.index ["company_id"], name: "idx_linkedin_profiles_company_id"
    t.index ["is_executive_role"], name: "idx_linkedin_profiles_executive_role"
    t.index ["linkedin_seniority_level"], name: "idx_linkedin_profiles_seniority_level"
    t.index ["phantom_run_id"], name: "idx_linkedin_leads_phantom_run"
    t.unique_constraint ["profile_url", "phantom_run_id"], name: "linkedin_leads_profile_url_phantom_run_id_key"
  end

  create_table "se", id: false, force: :cascade do |t|
    t.integer "id"
    t.text "domain"
    t.integer "http_error_code"
    t.text "http_error"
    t.text "html"
    t.text "updated_at"
    t.text "full_html"
    t.timestamptz "html_collected_at"
    t.integer "full_html_page_count"
    t.text "crawl_failed"
    t.timestamptz "crawl_failed_at"
    t.text "summary"
    t.boolean "is_commercial"
    t.text "category"
    t.datetime "summary_generated_at", precision: nil
    t.text "summary_failed_reason"
    t.text "description"
    t.text "linked_in"
    t.text "sps_match"
    t.text "sps_match_percentage"
    t.text "cleaned_html"
    t.timestamptz "html_cleaned_at"
    t.text "company_name"
    t.text "address"
    t.jsonb "main_products_services"
    t.jsonb "keywords"
    t.jsonb "technology"
    t.jsonb "contact_emails"
    t.text "webpage"
    t.text "industry"
    t.text "country"
  end

  create_table "se_bolagsverket", id: false, force: :cascade do |t|
    t.text "organisationsidentitet"
    t.integer "namnskyddslopnummer"
    t.text "registreringsland"
    t.text "organisationsnamn"
    t.text "organisationsform"
    t.text "avregistreringsdatum"
    t.text "avregistreringsorsak"
    t.text "pagandeAvvecklingsEllerOmstruktureringsforfarande"
    t.text "registreringsdatum"
    t.text "verksamhetsbeskrivning"
    t.text "postadress"
    t.bigint "id", null: false
  end

  create_table "service_configs", id: :serial, force: :cascade do |t|
    t.string "service_name", limit: 100, null: false
    t.integer "refresh_interval_days", default: 30
    t.text "depends_on_services", array: true
    t.boolean "is_active", default: true
    t.jsonb "config_data"
    t.datetime "created_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "updated_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.index ["service_name", "is_active"], name: "idx_service_configs_active"
    t.unique_constraint ["service_name"], name: "service_configs_service_name_key"
  end

  create_table "service_control_log", id: :serial, force: :cascade do |t|
    t.string "table_name", limit: 100, null: false
    t.integer "record_id", null: false
    t.string "service_name", limit: 100, null: false
    t.string "operation_type", limit: 50, null: false
    t.text "columns_affected", array: true
    t.string "status", limit: 20, default: "SUCCESS"
    t.text "error_message"
    t.integer "execution_time_ms"
    t.datetime "created_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "metadata"
    t.text "error_messages"
    t.jsonb "additional_data"
    t.string "target_table", limit: 255, comment: "Table being modified/updated by this operation (destination table). Different from table_name which is the source table being read from."
    t.index ["created_at"], name: "idx_sct_created_at"
    t.index ["service_name", "created_at"], name: "idx_service_control_service_time"
    t.index ["service_name", "target_table", "created_at"], name: "idx_service_control_log_service_target_table"
    t.index ["service_name"], name: "idx_sct_service_name"
    t.index ["status", "created_at"], name: "idx_service_control_status"
    t.index ["status"], name: "idx_sct_status"
    t.index ["table_name", "record_id"], name: "idx_service_control_table_record"
    t.index ["table_name", "status", "created_at"], name: "idx_service_control_table_status"
    t.index ["table_name"], name: "idx_sct_table_name"
    t.index ["target_table"], name: "idx_service_control_log_target_table"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
