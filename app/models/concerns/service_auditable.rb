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
    
    # For Company financial data, check business logic criteria first
    if self.class == Company && service_name == "company_financial_data"
      # Only process companies that match the business criteria
      return false unless source_registry == "brreg" && 
                         ordinary_result.nil? && 
                         ["AS", "ASA", "DA", "ANS"].include?(organization_form_code)
    end
    
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

      # Special handling for company services - use targeted scopes
      # When called on a scoped relation, merge the conditions
      if self == Company && service_name == "company_web_discovery"
        return all.merge(needing_web_discovery)
      elsif self == Company && service_name == "company_financial_data"
        return all.merge(needs_financial_update)
      elsif self == Company && service_name == "company_linkedin_discovery"
        return all.merge(needing_linkedin_discovery)
      elsif self == Person && service_name == "person_profile_extraction"
        return all.merge(needs_profile_extraction)
      elsif self == Person && service_name == "person_email_extraction"
        return all.merge(needs_email_extraction)
      elsif self == Person && service_name == "person_social_media_extraction"
        return all.merge(needs_social_media_extraction)
      end

      # Use a simpler subquery approach that mirrors the instance method logic
      refresh_threshold = service_config.refresh_interval_hours.hours.ago
      
      # Find records that either have no successful audit logs OR their most recent successful log is stale
      records_with_recent_success = ServiceAuditLog
        .where(auditable_type: name)
        .where(service_name: service_name)
        .where(status: ServiceAuditLog.statuses[:success])
        .where("completed_at >= ?", refresh_threshold)
        .select(:auditable_id)
        .distinct

      where.not(id: records_with_recent_success)
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
