module ServiceAuditable
  extend ActiveSupport::Concern

  included do
    # Polymorphic association to service audit logs
    has_many :service_audit_logs, as: :auditable, dependent: :destroy

    # Callbacks for automatic auditing
    after_create :audit_creation, if: :audit_enabled?
    after_update :audit_update, if: :audit_enabled?
  end

  # Instance methods
  def audit_service_operation(service_name, action: 'process', **options)
    audit_log = service_audit_logs.create!(
      service_name: service_name,
      action: action,
      **options
    )
    
    audit_log.mark_started!
    
    begin
      result = yield(audit_log)
      audit_log.mark_success! unless audit_log.status_success?
      result
    rescue StandardError => e
      audit_log.mark_failed!(e.message)
      raise
    end
  end

  def needs_service?(service_name)
    config = ServiceConfiguration.find_by(service_name: service_name)
    return false unless config&.active? # If no config or inactive, doesn't need service
    
    last_run = last_service_run(service_name)
    return true unless last_run # If no previous run, needs service
    
    # Check if last run is older than refresh interval
    refresh_threshold = config.refresh_interval_hours.hours.ago
    last_run.completed_at < refresh_threshold
  end

  def last_service_run(service_name)
    service_audit_logs
      .where(service_name: service_name, status: ServiceAuditLog.statuses[:success])
      .order(completed_at: :desc)
      .first
  end

  def audit_enabled?
    # Check Rails configuration, default to true
    # In test environment, allow overriding via environment variable
    if Rails.env.test?
      ENV['ENABLE_SERVICE_AUDITING'] == 'true' || 
        (Rails.application.config.respond_to?(:service_auditing_enabled) && 
         Rails.application.config.service_auditing_enabled)
    else
      Rails.application.config.respond_to?(:service_auditing_enabled) ? 
        Rails.application.config.service_auditing_enabled : true
    end
  end

  # Class methods
  class_methods do
    def with_service_audit(service_name, action: 'process', **options)
      ServiceAuditLog.batch_audit(all, service_name: service_name, action: action, **options) do |record, audit_log|
        yield(record, audit_log)
      end
    end

    def needing_service(service_name)
      config = ServiceConfiguration.find_by(service_name: service_name)
      return none unless config&.active? # If no config or inactive, return none
      
      refresh_threshold = config.refresh_interval_hours.hours.ago
      
      # Find records that either:
      # 1. Have no successful runs for this service
      # 2. Have their last successful run older than the refresh threshold
      left_joins_sql = <<-SQL
        LEFT JOIN (
          SELECT DISTINCT ON (auditable_id) 
            auditable_id, 
            completed_at
          FROM service_audit_logs 
          WHERE auditable_type = '#{name}' 
            AND service_name = '#{service_name}' 
            AND status = #{ServiceAuditLog.statuses[:success]}
          ORDER BY auditable_id, completed_at DESC
        ) latest_runs ON #{table_name}.id = latest_runs.auditable_id
      SQL
      
      joins(left_joins_sql)
        .where('latest_runs.auditable_id IS NULL OR latest_runs.completed_at < ?', refresh_threshold)
    end
  end

  private

  def audit_creation
    service_audit_logs.create!(
      service_name: 'automatic_audit',
      action: 'create',
      context: {
        'model_class' => self.class.name,
        'record_id' => id
      }
    )
  end

  def audit_update
    return unless saved_changes.present?
    
    service_audit_logs.create!(
      service_name: 'automatic_audit',
      action: 'update',
      changed_fields: saved_changes.keys,
      context: {
        'model_class' => self.class.name,
        'record_id' => id,
        'changes' => saved_changes
      }
    )
  end
end 