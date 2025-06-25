module ServiceAuditable
  extend ActiveSupport::Concern

  included do
    # Polymorphic association to service audit logs
    has_many :service_audit_logs, as: :auditable, dependent: :nullify
    has_many :latest_service_runs, as: :auditable
    has_many :records_needing_refresh, as: :auditable

    # Callbacks for automatic auditing
    unless Rails.env.test?
      after_create :audit_creation, if: -> { automatic_audit_enabled? }
      after_update :audit_update, if: -> { automatic_audit_enabled? }
    end
  end

  # Instance methods
  def audit_service_operation(service_name, operation_type: "process", **options)
    audit_log = ServiceAuditLog.create!(
      auditable: self,
      service_name: service_name,
      operation_type: operation_type,
      status: :pending,
      table_name: self.class.table_name,
      record_id: self.id.to_s,
      columns_affected: options[:columns_affected] || [ "unspecified" ],
      metadata: options[:metadata] || { "status" => "initialized" },
      started_at: Time.current
    )

    begin
      result = yield(audit_log)
      audit_log.mark_success!(options[:success_metadata] || {}, options[:columns_affected] || [])
      result
    rescue StandardError => e
      audit_log.mark_failed!(e.message, { "error" => e.message }, options[:columns_affected] || [])
      raise e
    end
  end

  def needs_service?(service_name)
    service_configuration = ServiceConfiguration.find_by(service_name: service_name)
    return false unless service_configuration&.active?
    last_run = last_service_run(service_name)
    return true unless last_run
    refresh_threshold = service_configuration.refresh_interval_hours.hours.ago
    last_run.completed_at < refresh_threshold
  end

  def last_service_run(service_name)
    service_audit_logs
      .for_service(service_name)
      .successful
      .order(completed_at: :desc)
      .first
  end

  def audit_enabled?
    return true unless Rails.env.test?
    if defined?(Rails.configuration) && Rails.configuration.respond_to?(:service_auditing_enabled)
      Rails.configuration.service_auditing_enabled
    else
      true
    end
  end

  def automatic_audit_enabled?
    return false if Rails.env.test?
    if defined?(Rails.configuration) && Rails.configuration.respond_to?(:automatic_auditing_enabled)
      Rails.configuration.automatic_auditing_enabled
    else
      true
    end
  end

  def with_service_audit(service_name, operation_type: "process", **options)
    records = options[:scope] || all

    records.find_each do |record|
      audit_log = ServiceAuditLog.create!(
        auditable: record,
        service_name: service_name,
        operation_type: operation_type,
        status: :pending,
        table_name: record.class.table_name,
        record_id: record.id.to_s,
        columns_affected: options[:columns_affected] || [ "unspecified" ],
        metadata: options[:metadata] || { "status" => "initialized" },
        started_at: Time.current
      )

      begin
        result = yield(record, audit_log)
        audit_log.mark_success!(options[:success_metadata] || {}, options[:columns_affected] || [])
        result
      rescue StandardError => e
        audit_log.mark_failed!(e.message, { "error" => e.message }, options[:columns_affected] || [])
        raise e
      end
    end
  end

  def audit_update(service_name, operation_type: "update", **options)
    records = options[:scope] || all

    records.find_each do |record|
      audit_log = ServiceAuditLog.create!(
        auditable: record,
        service_name: service_name,
        operation_type: operation_type,
        status: :pending,
        table_name: record.class.table_name,
        record_id: record.id.to_s,
        columns_affected: options[:columns_affected] || [ "unspecified" ],
        metadata: options[:metadata] || { "status" => "initialized" },
        started_at: Time.current
      )

      begin
        result = yield(record, audit_log)
        audit_log.mark_success!(options[:success_metadata] || {}, options[:columns_affected] || [])
        result
      rescue StandardError => e
        audit_log.mark_failed!(e.message, { "error" => e.message }, options[:columns_affected] || [])
        raise e
      end
    end
  end

  def needing_service(service_name)
    service_configuration = ServiceConfiguration.find_by(service_name: service_name)
    return [] unless service_configuration&.active?
    service_audit_logs
      .for_service(service_name)
      .successful
      .where("completed_at < ?", service_configuration.refresh_interval_hours.hours.ago)
  end

  # Class methods
  class_methods do
    def needing_service(service_name)
      service_config = ServiceConfiguration.find_by(service_name: service_name)
      return none unless service_config&.active?

      # Special handling for company_web_discovery - use custom scope
      if self == Company && service_name == "company_web_discovery"
        return needing_web_discovery
      end

      # Use a robust join for all AR models
      left = arel_table
      logs = ServiceAuditLog.arel_table
      join_cond = logs[:auditable_type].eq(name)
        .and(logs[:auditable_id].eq(left[:id]))
        .and(logs[:service_name].eq(service_name))
        .and(logs[:status].eq(ServiceAuditLog.statuses[:success]))

      joins(left.join(logs, Arel::Nodes::OuterJoin).on(join_cond).join_sources)
        .where("service_audit_logs.id IS NULL OR service_audit_logs.completed_at < ?",
               service_config.refresh_interval_hours.hours.ago)
    end
  end

  private

  def audit_creation
    return unless audit_enabled?
    service_audit_logs.create!(
      service_name: "automatic_audit",
      operation_type: "create",
      status: :success,
      auditable: self,
      table_name: self.class.table_name,
      record_id: self.id.to_s,
      columns_affected: [ "none" ],
      metadata: (attributes.presence || { error: "no metadata" }),
      started_at: created_at,
      completed_at: created_at
    )
  end

  def audit_update
    return unless audit_enabled?
    service_audit_logs.create!(
      service_name: "automatic_audit",
      operation_type: "update",
      status: :success,
      auditable: self,
      table_name: self.class.table_name,
      record_id: self.id.to_s,
      columns_affected: (saved_changes.keys.presence || [ "none" ]),
      metadata: (attributes.presence || { error: "no metadata" }),
      started_at: updated_at,
      completed_at: updated_at
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
