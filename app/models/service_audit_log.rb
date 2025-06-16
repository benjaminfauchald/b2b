class ServiceAuditLog < ApplicationRecord
  belongs_to :service_configuration, foreign_key: 'service_name', primary_key: 'service_name'
  belongs_to :auditable, polymorphic: true, optional: true

  validates :service_name, presence: true, length: { maximum: 100 }
  validates :action, presence: true, length: { maximum: 50 }
  validates :status, presence: true
  validates :context, presence: true

  enum status: {
    pending: 0,
    success: 1,
    failed: 2
  }

  scope :successful, -> { where(status: :success) }
  scope :failed, -> { where(status: :failed) }
  scope :pending, -> { where(status: :pending) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_service, ->(service_name) { where(service_name: service_name) }
  scope :for_auditable, ->(auditable) { where(auditable: auditable) }

  before_create :set_defaults

  def mark_started!
    update!(
      status: :pending,
      started_at: Time.current,
      completed_at: nil,
      duration_ms: nil
    )
  end

  def mark_completed!(duration_ms: nil)
    now = Time.current
    update!(
      completed_at: now,
      duration_ms: duration_ms || calculate_duration
    )
  end

  def mark_success!(context = {})
    update!(
      status: :success,
      completed_at: Time.current,
      duration_ms: calculate_duration,
      context: self.context.merge(context)
    )
  end

  def mark_failed!(error_message, context = {})
    update!(
      status: :failed,
      completed_at: Time.current,
      duration_ms: calculate_duration,
      error_message: error_message,
      context: self.context.merge(context)
    )
  end

  def calculate_duration
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).round
  end

  def add_context(data)
    update!(context: context.merge(data))
  end

  def track_changes(changes)
    update!(changed_fields: Array(changes))
  end

  def self.cleanup_old_logs(days = 90)
    where('created_at < ?', days.days.ago).delete_all
  end

  def self.batch_audit(records, service_name:, action: 'process', batch_size: 1000)
    records.each_slice(batch_size) do |batch|
      transaction do
        batch.each do |record|
          audit_log = create!(
            service_name: service_name,
            action: action,
            status: :pending,
            auditable: record,
            started_at: Time.current,
            context: {},
            changed_fields: []
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

  def self.create_for_service(service_name, action: 'process', auditable: nil)
    create!(
      service_name: service_name,
      action: action,
      status: :pending,
      auditable: auditable,
      started_at: Time.current,
      context: {},
      changed_fields: []
    )
  end

  private

  def set_defaults
    self.context ||= {}
    self.changed_fields ||= []
  end
end 