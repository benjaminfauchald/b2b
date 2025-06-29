# Optimized version of needing_service scope for better performance
module ServiceAuditableOptimized
  extend ActiveSupport::Concern

  class_methods do
    def needing_service_optimized(service_name)
      service_config = ServiceConfiguration.find_by(service_name: service_name)
      return none unless service_config&.active?

      # Use EXISTS subquery instead of NOT IN for better performance
      refresh_threshold = service_config.refresh_interval_hours.hours.ago
      
      where(<<-SQL)
        NOT EXISTS (
          SELECT 1 FROM service_audit_logs sal
          WHERE sal.auditable_type = '#{name}'
            AND sal.auditable_id = #{table_name}.id
            AND sal.service_name = '#{service_name}'
            AND sal.status = #{ServiceAuditLog.statuses[:success]}
            AND sal.completed_at >= '#{refresh_threshold.to_fs(:db)}'
        )
      SQL
    end
  end
end