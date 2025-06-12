class CreateServiceViews < ActiveRecord::Migration[8.0]
  def up
    # View for latest successful service runs per record/service combination
    execute <<-SQL
      CREATE VIEW latest_service_runs AS
      SELECT DISTINCT ON (auditable_type, auditable_id, service_name)
        auditable_type,
        auditable_id,
        service_name,
        status,
        completed_at,
        duration_ms,
        changed_fields,
        context,
        id as audit_log_id
      FROM service_audit_logs
      WHERE status = 1 -- success status
      ORDER BY auditable_type, auditable_id, service_name, completed_at DESC;
    SQL
    
    # View for service performance statistics
    execute <<-SQL
      CREATE VIEW service_performance_stats AS
      SELECT 
        service_name,
        COUNT(*) as total_runs,
        COUNT(CASE WHEN status = 1 THEN 1 END) as successful_runs,
        COUNT(CASE WHEN status = 2 THEN 1 END) as failed_runs,
        COUNT(CASE WHEN status = 0 THEN 1 END) as pending_runs,
        ROUND(AVG(duration_ms), 2) as avg_duration_ms,
        MIN(duration_ms) as min_duration_ms,
        MAX(duration_ms) as max_duration_ms,
        ROUND(
          (COUNT(CASE WHEN status = 1 THEN 1 END) * 100.0 / COUNT(*)), 2
        ) as success_rate_percent,
        MIN(created_at) as first_run_at,
        MAX(created_at) as last_run_at
      FROM service_audit_logs
      WHERE completed_at IS NOT NULL
      GROUP BY service_name;
    SQL
    
    # View for records needing refresh based on service configurations
    execute <<-SQL
      CREATE VIEW records_needing_refresh AS
      SELECT DISTINCT
        sal.auditable_type,
        sal.auditable_id,
        sal.service_name,
        sc.refresh_interval_hours,
        lsr.completed_at as last_successful_run,
        NOW() - INTERVAL '1 hour' * sc.refresh_interval_hours as refresh_threshold,
        CASE 
          WHEN lsr.completed_at IS NULL THEN true
          WHEN lsr.completed_at < (NOW() - INTERVAL '1 hour' * sc.refresh_interval_hours) THEN true
          ELSE false
        END as needs_refresh
      FROM service_audit_logs sal
      INNER JOIN service_configurations sc ON sc.service_name = sal.service_name
      LEFT JOIN latest_service_runs lsr ON (
        lsr.auditable_type = sal.auditable_type AND 
        lsr.auditable_id = sal.auditable_id AND 
        lsr.service_name = sal.service_name
      )
      WHERE sc.active = true;
    SQL
  end
  
  def down
    execute "DROP VIEW IF EXISTS records_needing_refresh;"
    execute "DROP VIEW IF EXISTS service_performance_stats;"
    execute "DROP VIEW IF EXISTS latest_service_runs;"
  end
end
