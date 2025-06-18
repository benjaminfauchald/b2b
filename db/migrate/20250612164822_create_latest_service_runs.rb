class CreateLatestServiceRuns < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      CREATE MATERIALIZED VIEW latest_service_runs AS
      WITH latest_runs AS (
        SELECT DISTINCT ON (service_name, auditable_type, auditable_id)
          id as audit_log_id,
          service_name,
          auditable_type,
          auditable_id,
          action,
          status,
          started_at,
          completed_at,
          duration_ms,
          error_message,
          context,
          created_at
        FROM service_audit_logs
        ORDER BY service_name, auditable_type, auditable_id, completed_at DESC NULLS LAST
      )
      SELECT * FROM latest_runs;

      CREATE UNIQUE INDEX idx_latest_service_runs_unique 
      ON latest_service_runs(service_name, auditable_type, auditable_id);
    SQL
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS latest_service_runs;"
  end
end 