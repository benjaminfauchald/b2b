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

ActiveRecord::Schema[8.0].define(version: 2025_06_16_182357) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "message_id", "message_checksum" ], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "record_type", "record_id", "name" ], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index [ "blob_id" ], name: "index_active_storage_attachments_on_blob_id"
    t.index [ "record_type", "record_id", "name", "blob_id" ], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index [ "key" ], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index [ "blob_id", "variation_digest" ], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "brreg", id: false, force: :cascade do |t|
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

  create_table "brreg2_old", id: false, force: :cascade do |t|
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
    t.boolean "vat_registered"
    t.date "vat_registration_date"
    t.boolean "voluntary_vat_registered"
    t.date "voluntary_vat_registration_date"
    t.boolean "bankruptcy"
    t.date "bankruptcy_date"
    t.boolean "under_liquidation"
    t.date "liquidation_date"
    t.decimal "revenue"
    t.decimal "profit"
    t.decimal "equity"
    t.decimal "total_assets"
    t.decimal "current_assets"
    t.decimal "fixed_assets"
    t.decimal "current_liabilities"
    t.decimal "long_term_liabilities"
    t.integer "year"
    t.text "financial_data"
    t.index [ "linkedin_ai_url" ], name: "index_companies_on_linkedin_ai_url"
    t.index [ "operating_revenue" ], name: "index_companies_on_operating_revenue"
    t.index [ "organization_form_description" ], name: "index_companies_on_organization_form_description"
    t.index [ "registration_number" ], name: "index_companies_on_registration_number_unique", unique: true
    t.index [ "source_country", "source_registry" ], name: "index_companies_on_source_country_and_source_registry"
  end

  create_table "domains", force: :cascade do |t|
    t.string "domain"
    t.boolean "www"
    t.boolean "mx"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "dns"
    t.string "mx_error"
  end

  create_table "domains_se_raw", id: false, force: :cascade do |t|
    t.text "c1"
  end

  create_table "service_audit_logs", force: :cascade do |t|
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.string "service_name", limit: 100, null: false
    t.string "operation_type", limit: 50, default: "process", null: false
    t.integer "status", default: 0, null: false
    t.text "columns_affected", default: [], array: true
    t.text "error_message"
    t.integer "execution_time_ms"
    t.jsonb "metadata", default: {}
    t.string "job_id"
    t.string "queue_name"
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "table_name", default: "", null: false
    t.string "target_table"
    t.string "record_id"
    t.index [ "auditable_type", "auditable_id", "service_name" ], name: "index_service_audit_logs_on_auditable_and_service"
    t.index [ "auditable_type", "auditable_id" ], name: "index_service_audit_logs_on_auditable"
    t.index [ "created_at" ], name: "index_service_audit_logs_on_created_at"
    t.index [ "metadata" ], name: "index_service_audit_logs_on_metadata", using: :gin
    t.index [ "record_id" ], name: "index_service_audit_logs_on_record_id"
    t.index [ "service_name", "status", "created_at" ], name: "index_service_audit_logs_on_service_status_created"
    t.index [ "service_name" ], name: "index_service_audit_logs_on_service_name"
    t.index [ "status" ], name: "index_service_audit_logs_on_status"
    t.index [ "table_name" ], name: "index_service_audit_logs_on_table_name"
    t.index [ "target_table" ], name: "index_service_audit_logs_on_target_table"
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
    t.index [ "active" ], name: "index_service_configurations_on_active"
    t.index [ "service_name" ], name: "index_service_configurations_on_service_name", unique: true
    t.index [ "settings" ], name: "index_service_configurations_on_settings", using: :gin
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role"
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "email_provider"
    t.datetime "last_enhanced_at"
    t.index [ "email" ], name: "index_users_on_email", unique: true
    t.index [ "reset_password_token" ], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
end
