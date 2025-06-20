class CreateServicePerformanceStats < ActiveRecord::Migration[8.0]
  def up
    execute "DROP MATERIALIZED VIEW IF EXISTS service_performance_stats;"
    execute <<-SQL
      CREATE MATERIALIZED VIEW service_performance_stats AS
      WITH stats AS (
        SELECT#{' '}
          service_name,
          COUNT(*) as total_runs,
          COUNT(*) FILTER (WHERE status = 1) as successful_runs,
          COUNT(*) FILTER (WHERE status = 2) as failed_runs,
          AVG(duration_ms) FILTER (WHERE status = 1) as avg_duration_ms,
          MIN(duration_ms) FILTER (WHERE status = 1) as min_duration_ms,
          MAX(duration_ms) FILTER (WHERE status = 1) as max_duration_ms,
          COUNT(*) FILTER (WHERE status = 1 AND completed_at > NOW() - INTERVAL '1 hour') as successful_runs_last_hour,
          COUNT(*) FILTER (WHERE status = 2 AND completed_at > NOW() - INTERVAL '1 hour') as failed_runs_last_hour
        FROM service_audit_logs
        GROUP BY service_name
      )
      SELECT#{' '}
        service_name,
        total_runs,
        successful_runs,
        failed_runs,
        CASE#{' '}
          WHEN total_runs > 0 THEN (successful_runs::float / total_runs * 100)
          ELSE 0
        END as success_rate_percent,
        avg_duration_ms,
        min_duration_ms,
        max_duration_ms,
        successful_runs_last_hour,
        failed_runs_last_hour,
        CASE#{' '}
          WHEN (successful_runs_last_hour + failed_runs_last_hour) > 0#{' '}
          THEN (failed_runs_last_hour::float / (successful_runs_last_hour + failed_runs_last_hour) * 100)
          ELSE 0
        END as failure_rate_last_hour,
        NOW() as last_updated_at
      FROM stats;

      CREATE UNIQUE INDEX idx_service_performance_stats_service_name#{' '}
      ON service_performance_stats(service_name);
    SQL
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS service_performance_stats;"
  end
end
