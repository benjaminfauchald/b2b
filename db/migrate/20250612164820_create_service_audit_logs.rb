class CreateServiceAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :service_audit_logs do |t|
      # Polymorphic association for auditable records
      t.references :auditable, polymorphic: true, null: false, index: true

      # Service identification and action
      t.string :service_name, limit: 100, null: false
      t.string :action, limit: 50, null: false, default: 'process'

      # Status tracking (enum: pending=0, success=1, failed=2)
      t.integer :status, null: false, default: 0

      # Change tracking and error handling
      t.text :changed_fields, array: true, default: []
      t.text :error_message

      # Performance tracking
      t.integer :duration_ms

      # Flexible context storage
      t.jsonb :context, default: {}

      # Job and queue information
      t.string :job_id
      t.string :queue_name

      # Timing information
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    # Strategic indexes for performance
    add_index :service_audit_logs, :service_name
    add_index :service_audit_logs, :status
    add_index :service_audit_logs, :created_at
    add_index :service_audit_logs, [ :auditable_type, :auditable_id, :service_name ],
              name: 'index_service_audit_logs_on_auditable_and_service'
    add_index :service_audit_logs, [ :service_name, :status, :created_at ],
              name: 'index_service_audit_logs_on_service_status_created'
    add_index :service_audit_logs, :context, using: :gin
  end
end
