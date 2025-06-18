class CreateServicePerformanceStatsView < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      DROP MATERIALIZED VIEW IF EXISTS service_performance_stats;
      CREATE OR REPLACE VIEW service_performance_stats AS
      SELECT#{' '}
        service_name,
        COUNT(*) as total_runs,
        ROUND(100.0 * COUNT(*) FILTER (WHERE status = 1) / COUNT(*), 2) as success_rate_percent,
        ROUND(AVG(duration_ms), 2) as avg_duration_ms,
        MIN(created_at) as first_run_at,
        MAX(created_at) as last_run_at
      FROM service_audit_logs
      GROUP BY service_name;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS service_performance_stats;"
  end
end
