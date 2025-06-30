# Optimized version of needing_service scope for better performance
module ServiceAuditableOptimized
  extend ActiveSupport::Concern

  class_methods do
    def needing_service_optimized(service_name)
      service_config = ServiceConfiguration.find_by(service_name: service_name)
      return none unless service_config&.active?

      # Use EXISTS subquery instead of NOT IN for better performance
      refresh_threshold = service_config.refresh_interval_hours.hours.ago

      where(<<-SQL, auditable_type: name, service_name: service_name, status: ServiceAuditLog.statuses[:success], threshold: refresh_threshold)
        NOT EXISTS (
          SELECT 1 FROM service_audit_logs sal
          WHERE sal.auditable_type = :auditable_type
            AND sal.auditable_id = #{table_name}.id
            AND sal.service_name = :service_name
            AND sal.status = :status
            AND sal.completed_at >= :threshold
        )
      SQL
    end
  end
end
