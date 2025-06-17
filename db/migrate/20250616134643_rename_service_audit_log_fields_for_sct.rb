class RenameServiceAuditLogFieldsForSct < ActiveRecord::Migration[8.0]
  def change
    rename_column :service_audit_logs, :action, :operation_type
    rename_column :service_audit_logs, :changed_fields, :columns_affected
    rename_column :service_audit_logs, :duration_ms, :execution_time_ms
    rename_column :service_audit_logs, :context, :metadata
  end
end
