class ServiceAuditLog < ApplicationRecord
  # Status constants
  STATUS_PENDING = 0
  STATUS_SUCCESS = 1
  STATUS_FAILED = 2

  # Rails 8 enum for status
  enum :status, { pending: 0, success: 1, failed: 2 }

  # Associations
  belongs_to :service_configuration, foreign_key: 'service_name', primary_key: 'service_name', optional: true
  belongs_to :auditable, polymorphic: true, optional: false

  # Validations
  validates :service_name, presence: true, length: { maximum: 100 }
  validates :table_name, presence: true
  validates :operation_type, presence: true, length: { maximum: 50 }
  validates :status, presence: true
  validates :auditable, presence: true
  validates :execution_time_ms, numericality: { allow_nil: true }
  validates :record_id, presence: true
  validates :columns_affected, presence: true
  validate :columns_affected_not_empty
  validates :metadata, presence: true
  validate :metadata_must_have_error_if_failed
  # target_table is optional (nullable)

  # Scopes
  scope :successful, -> { where(status: STATUS_SUCCESS) }
  scope :failed, -> { where(status: STATUS_FAILED) }
  scope :pending, -> { where(status: STATUS_PENDING) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_service, ->(service_name) { where(service_name: service_name) }
  scope :for_auditable, ->(auditable) { where(auditable: auditable) }

  before_create :set_defaults

  validate :metadata_not_nil
  validate :columns_affected_not_nil

  def mark_started!
    update!(
      status: STATUS_PENDING,
      started_at: Time.current,
      completed_at: nil,
      execution_time_ms: nil
    )
  end

  def mark_completed!(execution_time_ms: nil)
    now = Time.current
    update!(
      completed_at: now,
      execution_time_ms: execution_time_ms || calculate_duration
    )
  end

  def mark_success!(metadata = {}, columns_affected = [])
    now = Time.current
    update_columns(
      status: STATUS_SUCCESS,
      completed_at: now,
      metadata: metadata,
      columns_affected: columns_affected
    )
    update_column(:execution_time_ms, calculate_duration)
  end

  def mark_failed!(error_message, metadata = {}, columns_affected = [])
    now = Time.current
    update_columns(
      status: STATUS_FAILED,
      error_message: error_message,
      completed_at: now,
      metadata: metadata,
      columns_affected: columns_affected
    )
    update_column(:execution_time_ms, calculate_duration)
  end

  def calculate_duration
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).round
  end

  def add_metadata(data)
    update!(metadata: metadata.merge(data))
  end

  def track_columns(columns)
    update!(columns_affected: Array(columns))
  end

  def self.cleanup_old_logs(days = 90)
    where('created_at < ?', days.days.ago).delete_all
  end

  def self.batch_audit(records, service_name:, operation_type: 'process', batch_size: 1000)
    records.each_slice(batch_size) do |batch|
      transaction do
        batch.each do |record|
          audit_log = create!(
            service_name: service_name,
            table_name: record.class.table_name,
            target_table: nil,
            record_id: record.id,
            operation_type: operation_type,
            status: STATUS_PENDING,
            auditable: record,
            started_at: Time.current,
            metadata: {},
            columns_affected: [],
            execution_time_ms: nil
          )

          begin
            yield(record, audit_log)
            audit_log.mark_success!
          rescue StandardError => e
            audit_log.mark_failed!(e.message)
            raise
          end
        end
      end
    end
  end

  def self.create_for_service(service_name, operation_type: 'process', auditable: nil)
    create!(
      service_name: service_name,
      table_name: auditable&.class&.table_name,
      target_table: nil,
      record_id: auditable&.id,
      operation_type: operation_type,
      status: STATUS_PENDING,
      auditable: auditable,
      started_at: Time.current,
      metadata: {},
      columns_affected: [],
      execution_time_ms: nil
    )
  end

  private

  def set_defaults
    self.metadata ||= {}
    self.columns_affected ||= []
    self.table_name ||= auditable&.class&.table_name || ''
    self.record_id ||= auditable&.id&.to_s
  end

  def metadata_not_nil
    errors.add(:metadata, "can't be nil") if metadata.nil?
  end

  def columns_affected_not_nil
    errors.add(:columns_affected, "can't be nil") if columns_affected.nil?
  end

  def columns_affected_not_empty
    if columns_affected.blank? || (columns_affected.respond_to?(:empty?) && columns_affected.empty?)
      errors.add(:columns_affected, "can't be blank")
    end
  end

  def metadata_must_have_error_if_failed
    if status == "failed" && (!metadata.is_a?(Hash) || !metadata.key?("error") || metadata["error"].blank?)
      errors.add(:metadata, "must include an 'error' key with the error message when status is failed")
    end
  end
end 