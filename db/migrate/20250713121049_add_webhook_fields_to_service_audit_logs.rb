class AddWebhookFieldsToServiceAuditLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :service_audit_logs, :webhook_payload, :jsonb
    add_column :service_audit_logs, :phantom_container_id, :string
  end
end
