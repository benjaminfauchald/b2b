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

ActiveRecord::Schema[8.0].define(version: 2025_06_13_044019) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "brreg", force: :cascade do |t|
    t.string "organisasjonsnummer", null: false
    t.text "navn", null: false
    t.text "organisasjonsform_kode"
    t.text "organisasjonsform_beskrivelse"
    t.text "naeringskode1_kode"
    t.text "naeringskode1_beskrivelse"
    t.text "naeringskode2_kode"
    t.text "naeringskode2_beskrivelse"
    t.text "naeringskode3_kode"
    t.text "naeringskode3_beskrivelse"
    t.text "aktivitet"
    t.integer "antallansatte"
    t.text "hjemmeside"
    t.text "epost"
    t.text "telefon"
    t.text "mobiltelefon"
    t.text "forretningsadresse"
    t.text "forretningsadresse_poststed"
    t.text "forretningsadresse_postnummer"
    t.text "forretningsadresse_kommune"
    t.text "forretningsadresse_land"
    t.bigint "driftsinntekter"
    t.bigint "driftskostnad"
    t.bigint "ordinaertResultat"
    t.bigint "aarsresultat"
    t.boolean "mvaregistrert"
    t.date "mvaregistrertdato"
    t.boolean "frivilligmvaregistrert"
    t.date "frivilligmvaregistrertdato"
    t.date "stiftelsesdato"
    t.boolean "konkurs"
    t.date "konkursdato"
    t.boolean "underavvikling"
    t.date "avviklingsdato"
    t.text "linked_in"
    t.text "linked_in_ai"
    t.jsonb "linked_in_alternatives"
    t.boolean "linked_in_processed", default: false
    t.datetime "linked_in_last_processed_at"
    t.integer "http_error"
    t.text "http_error_message"
    t.jsonb "brreg_result_raw"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["driftsinntekter"], name: "index_brreg_on_driftsinntekter"
    t.index ["linked_in_ai"], name: "index_brreg_on_linked_in_ai"
    t.index ["organisasjonsform_beskrivelse"], name: "index_brreg_on_organisasjonsform_beskrivelse"
    t.index ["organisasjonsnummer"], name: "index_brreg_on_organisasjonsnummer", unique: true
  end

  create_table "brreg2", id: false, force: :cascade do |t|
    t.integer "organisasjonsnummer"
    t.text "navn"
    t.text "organisasjonsform_kode"
    t.text "organisasjonsform_beskrivelse"
    t.decimal "naeringskode1_kode"
    t.text "naeringskode1_beskrivelse"
    t.text "naeringskode2_kode"
    t.text "naeringskode2_beskrivelse"
    t.text "naeringskode3_kode"
    t.text "naeringskode3_beskrivelse"
    t.decimal "hjelpeenhetskode_kode"
    t.text "hjelpeenhetskode_beskrivelse"
    t.text "harregistrertantallansatte"
    t.text "antallansatte"
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
    t.integer "ordinaertresultat"
    t.integer "aarsresultat"
    t.integer "driftsinntekter"
    t.integer "driftskostnad"
    t.text "http_error"
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
    t.text "linked_in_alternatives"
    t.text "brreg_result_raw"
    t.text "segment"
  end

  create_table "communications", force: :cascade do |t|
    t.datetime "timestamp"
    t.string "event_type"
    t.string "campaign_name"
    t.string "workspace"
    t.string "campaign_id"
    t.string "service"
    t.string "connection_attempt_type"
    t.string "lead_email"
    t.string "first_name"
    t.string "last_name"
    t.string "company_name"
    t.string "website"
    t.string "phone"
    t.integer "step"
    t.string "email_account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "companies", force: :cascade do |t|
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
    t.integer "last_submitted_annual_report"
    t.bigint "ordinary_result"
    t.bigint "annual_result"
    t.bigint "operating_revenue"
    t.bigint "operating_costs"
    t.text "linkedin_url"
    t.text "linkedin_ai_url"
    t.text "linkedin_alt_url"
    t.jsonb "linkedin_alternatives"
    t.boolean "linkedin_processed", default: false
    t.datetime "linkedin_last_processed_at"
    t.integer "linkedin_ai_confidence"
    t.text "sps_match"
    t.text "sps_match_percentage"
    t.integer "http_error"
    t.text "http_error_message"
    t.jsonb "source_raw_data"
    t.integer "brreg_id"
    t.string "country", limit: 2
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["linkedin_ai_url"], name: "index_companies_on_linkedin_ai_url"
    t.index ["operating_revenue"], name: "index_companies_on_operating_revenue"
    t.index ["organization_form_description"], name: "index_companies_on_organization_form_description"
    t.index ["source_country", "source_registry"], name: "index_companies_on_source_country_and_source_registry"
  end

  create_table "domains", force: :cascade do |t|
    t.string "domain"
    t.boolean "www"
    t.boolean "mx"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "dns"
  end

  create_table "service_audit_logs", force: :cascade do |t|
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.string "service_name", limit: 100, null: false
    t.string "action", limit: 50, default: "process", null: false
    t.integer "status", default: 0, null: false
    t.text "changed_fields", default: [], array: true
    t.text "error_message"
    t.integer "duration_ms"
    t.jsonb "context", default: {}
    t.string "job_id"
    t.string "queue_name"
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auditable_type", "auditable_id", "service_name"], name: "index_service_audit_logs_on_auditable_and_service"
    t.index ["auditable_type", "auditable_id"], name: "index_service_audit_logs_on_auditable"
    t.index ["context"], name: "index_service_audit_logs_on_context", using: :gin
    t.index ["created_at"], name: "index_service_audit_logs_on_created_at"
    t.index ["service_name", "status", "created_at"], name: "index_service_audit_logs_on_service_status_created"
    t.index ["service_name"], name: "index_service_audit_logs_on_service_name"
    t.index ["status"], name: "index_service_audit_logs_on_status"
  end

  create_table "service_configurations", force: :cascade do |t|
    t.string "service_name", limit: 100, null: false
    t.integer "refresh_interval_hours", default: 720
    t.text "depends_on_services", default: [], array: true
    t.boolean "active", default: true, null: false
    t.integer "batch_size", default: 1000
    t.integer "retry_attempts", default: 3
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_configurations_on_active"
    t.index ["service_name"], name: "index_service_configurations_on_service_name", unique: true
    t.index ["settings"], name: "index_service_configurations_on_settings", using: :gin
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
