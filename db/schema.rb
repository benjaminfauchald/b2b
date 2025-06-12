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

ActiveRecord::Schema[8.0].define(version: 2025_06_12_164835) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
