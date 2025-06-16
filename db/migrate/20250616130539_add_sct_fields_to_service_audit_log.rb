class AddSctFieldsToServiceAuditLog < ActiveRecord::Migration[7.1]
  def change
    add_column :service_audit_logs, :table_name, :string, null: false, default: ''
    add_column :service_audit_logs, :target_table, :string
    add_column :service_audit_logs, :record_id, :string
    add_index :service_audit_logs, :table_name
    add_index :service_audit_logs, :target_table
    add_index :service_audit_logs, :record_id
  end
end
