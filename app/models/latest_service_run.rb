class LatestServiceRun < ApplicationRecord
  # This is a read-only view model
  self.table_name = "latest_service_runs"
  # Rails 8 uses symbol arrays for composite primary keys
  # (string arrays can raise argument-arity errors during initialisation)
  self.primary_key = %i[service_name auditable_type auditable_id]

  # Make it read-only
  def readonly?
    true
  end

  # Associations
  belongs_to :auditable, polymorphic: true
  belongs_to :audit_log, class_name: "ServiceAuditLog", foreign_key: "audit_log_id"

  # Scopes
  scope :for_service, ->(name) { where(service_name: name) }
  scope :for_auditable_type, ->(type) { where(auditable_type: type) }
  scope :recent, -> { order(completed_at: :desc) }

  # Class methods
  def self.for_auditable(record)
    where(auditable_type: record.class.name, auditable_id: record.id)
  end

  def self.latest_for_service_and_record(service_name, record)
    where(
      service_name: service_name,
      auditable_type: record.class.name,
      auditable_id: record.id
    ).first
  end

  def self.refresh
    connection.execute("REFRESH MATERIALIZED VIEW latest_service_runs")
  end

  def self.find_by_auditable(service_name, auditable)
    find_by(
      service_name: service_name,
      auditable_type: auditable.class.name,
      auditable_id: auditable.id
    )
  end

  # Instance methods
  def auditable
    auditable_type.constantize.find(auditable_id)
  end

  def age_in_hours
    return nil unless completed_at

    ((Time.current - completed_at) / 1.hour).round(2)
  end

  def duration_in_seconds
    return nil unless duration_ms

    (duration_ms / 1000.0).round(2)
  end

  def duration_seconds
    duration_ms.to_f / 1000 if duration_ms
  end

  def success?
    status == "success"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending"
  end
end
