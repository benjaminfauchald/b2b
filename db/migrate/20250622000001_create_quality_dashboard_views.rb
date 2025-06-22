class CreateQualityDashboardViews < ActiveRecord::Migration[8.0]
  def up
    # Create daily_service_stats materialized view
    execute <<-SQL
      CREATE MATERIALIZED VIEW daily_service_stats AS
      WITH service_stats AS (
        SELECT
          service_name,
          DATE(created_at) AS date,
          COUNT(*) AS total_runs,
          COUNT(CASE WHEN status = 1 THEN 1 END) AS successful_runs,
          COUNT(CASE WHEN status = 2 THEN 1 END) AS failed_runs,
          AVG(execution_time_ms) AS avg_execution_time_ms,
          PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY execution_time_ms) AS p95_execution_time_ms,
          PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY execution_time_ms) AS p99_execution_time_ms,
          ROUND((COUNT(CASE WHEN status = 2 THEN 1 END)::FLOAT / NULLIF(COUNT(*), 0)) * 100, 2) AS error_rate,
          MIN(created_at) AS first_run_at,
          MAX(created_at) AS last_run_at
        FROM
          service_audit_logs
        WHERE
          execution_time_ms IS NOT NULL
        GROUP BY
          service_name, DATE(created_at)
      )
      SELECT
        ROW_NUMBER() OVER() AS id,
        service_name,
        date,
        total_runs,
        successful_runs,
        failed_runs,
        COALESCE(avg_execution_time_ms, 0) AS avg_execution_time_ms,
        COALESCE(p95_execution_time_ms, 0) AS p95_execution_time_ms,
        COALESCE(p99_execution_time_ms, 0) AS p99_execution_time_ms,
        COALESCE(error_rate, 0) AS error_rate,
        first_run_at,
        last_run_at
      FROM
        service_stats
      ORDER BY
        date DESC, service_name
    SQL

    # Create hourly_service_stats materialized view
    execute <<-SQL
      CREATE MATERIALIZED VIEW hourly_service_stats AS
      WITH service_stats AS (
        SELECT
          service_name,
          DATE(created_at) AS date,
          EXTRACT(HOUR FROM created_at) AS hour,
          COUNT(*) AS total_runs,
          COUNT(CASE WHEN status = 1 THEN 1 END) AS successful_runs,
          COUNT(CASE WHEN status = 2 THEN 1 END) AS failed_runs,
          AVG(execution_time_ms) AS avg_execution_time_ms,
          PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY execution_time_ms) AS p95_execution_time_ms,
          PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY execution_time_ms) AS p99_execution_time_ms,
          ROUND((COUNT(CASE WHEN status = 2 THEN 1 END)::FLOAT / NULLIF(COUNT(*), 0)) * 100, 2) AS error_rate,
          MIN(created_at) AS first_run_at,
          MAX(created_at) AS last_run_at
        FROM
          service_audit_logs
        WHERE
          execution_time_ms IS NOT NULL
        GROUP BY
          service_name, DATE(created_at), EXTRACT(HOUR FROM created_at)
      )
      SELECT
        ROW_NUMBER() OVER() AS id,
        service_name,
        date,
        hour,
        total_runs,
        successful_runs,
        failed_runs,
        COALESCE(avg_execution_time_ms, 0) AS avg_execution_time_ms,
        COALESCE(p95_execution_time_ms, 0) AS p95_execution_time_ms,
        COALESCE(p99_execution_time_ms, 0) AS p99_execution_time_ms,
        COALESCE(error_rate, 0) AS error_rate,
        first_run_at,
        last_run_at
      FROM
        service_stats
      ORDER BY
        date DESC, hour DESC, service_name
    SQL

    # Create indexes for faster querying
    execute <<-SQL
      CREATE UNIQUE INDEX idx_daily_service_stats_id ON daily_service_stats(id);
      CREATE INDEX idx_daily_service_stats_service_name ON daily_service_stats(service_name);
      CREATE INDEX idx_daily_service_stats_date ON daily_service_stats(date);
      CREATE INDEX idx_daily_service_stats_error_rate ON daily_service_stats(error_rate DESC);
      
      CREATE UNIQUE INDEX idx_hourly_service_stats_id ON hourly_service_stats(id);
      CREATE INDEX idx_hourly_service_stats_service_name ON hourly_service_stats(service_name);
      CREATE INDEX idx_hourly_service_stats_date_hour ON hourly_service_stats(date, hour);
      CREATE INDEX idx_hourly_service_stats_error_rate ON hourly_service_stats(error_rate DESC);
    SQL
  end

  def down
    execute <<-SQL
      DROP MATERIALIZED VIEW IF EXISTS daily_service_stats;
      DROP MATERIALIZED VIEW IF EXISTS hourly_service_stats;
    SQL
  end
end
