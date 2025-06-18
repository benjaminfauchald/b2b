class CreateRecordsNeedingRefresh < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      CREATE OR REPLACE VIEW records_needing_refresh AS
      WITH configs AS (
        SELECT#{' '}
          service_name,
          refresh_interval_hours,
          active
        FROM service_configurations
      ),
      latest_runs AS (
        SELECT#{' '}
          service_name,
          auditable_type,
          auditable_id,
          completed_at
        FROM latest_service_runs
        WHERE status = 1
      )
      SELECT#{' '}
        c.service_name,
        l.auditable_type,
        l.auditable_id,
        CASE#{' '}
          WHEN l.completed_at IS NULL THEN true
          WHEN l.completed_at < (NOW() - (COALESCE(c.refresh_interval_hours, 24)) * INTERVAL '1 hour') THEN true
          ELSE false
        END as needs_refresh
      FROM configs c
      CROSS JOIN (
        SELECT DISTINCT auditable_type, auditable_id
        FROM service_audit_logs
      ) a
      LEFT JOIN latest_runs l ON#{' '}
        l.service_name = c.service_name AND
        l.auditable_type = a.auditable_type AND
        l.auditable_id = a.auditable_id
      WHERE c.active = true;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS records_needing_refresh;"
  end
end
