module ServiceAuditable
  extend ActiveSupport::Concern

  included do
    # Polymorphic association to service audit logs
    has_many :service_audit_logs, as: :auditable, dependent: :destroy

    # Callbacks for automatic auditing
    unless Rails.env.test?
      after_create :audit_creation, if: -> { automatic_audit_enabled? }
      after_update :audit_update, if: -> { automatic_audit_enabled? }
    end
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
    Rails.application.config.service_auditing_enabled
  end

  def automatic_audit_enabled?
    if Rails.env.test?
      ENV['ENABLE_AUTOMATIC_AUDITING'] == 'true'
    else
      Rails.application.config.respond_to?(:automatic_auditing_enabled) ? Rails.application.config.automatic_auditing_enabled != false : true
    end
  end

  # Class methods
  class_methods do
    def with_service_audit(service_name, action: 'process', **options)
      all.each do |record|
        record.audit_service_operation(service_name, action: action, **options) do |audit_log|
          yield(record, audit_log)
        end
      end
    end

    def needing_service(service_name)
      config = ServiceConfiguration.find_by(service_name: service_name)
      return [] unless config&.active?

      refresh_threshold = config.refresh_interval_hours.hours.ago

      # Find records that either:
      # 1. Have never been processed by this service
      # 2. Have only failed attempts
      # 3. Have a successful run older than the refresh interval
      where.not(
        id: ServiceAuditLog
          .where(auditable_type: name, service_name: service_name, status: ServiceAuditLog.statuses[:success])
          .where('completed_at > ?', refresh_threshold)
          .select(:auditable_id)
      )
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
    service_audit_logs.create!(
      service_name: 'automatic_audit',
      action: 'update',
      context: {
        'model_class' => self.class.name,
        'record_id' => id
      },
      changed_fields: changed
    )
  end
end

# Module methods for thread-local auditing control
module ServiceAuditable
  def self.automatic_auditing_disabled?
    Thread.current[:automatic_auditing_disabled] == true
  end

  def self.with_automatic_auditing_disabled
    previous = Thread.current[:automatic_auditing_disabled]
    Thread.current[:automatic_auditing_disabled] = true
    yield
  ensure
    Thread.current[:automatic_auditing_disabled] = previous
  end
end 