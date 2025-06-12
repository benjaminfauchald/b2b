class ServiceAuditLog < ApplicationRecord
  # Polymorphic association for auditable records
  belongs_to :auditable, polymorphic: true

  # Validations
  validates :service_name, presence: true, length: { maximum: 100 }
  validates :action, presence: true, length: { maximum: 50 }

  # Enums for status with prefix
  enum :status, { pending: 0, success: 1, failed: 2 }, prefix: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_service, ->(name) { where(service_name: name) }
  scope :successful, -> { where(status: :success) }
  scope :failed, -> { where(status: :failed) }
  scope :for_auditable, ->(record) { where(auditable: record) }

  # Instance methods
  def mark_started!
    update!(started_at: Time.current)
  end

  def mark_completed!
    now = Time.current
    duration = started_at ? ((now - started_at) * 1000).round : nil
    update!(completed_at: now, duration_ms: duration)
  end

  def mark_success!(context_data = {})
    add_context(context_data) if context_data.present?
    mark_completed!
    update!(status: :success)
  end

  def mark_failed!(error_message = nil, context_data = {})
    add_context(context_data) if context_data.present?
    mark_completed!
    update!(status: :failed, error_message: error_message)
  end

  def add_context(data)
    self.context = (context || {}).merge(data.stringify_keys)
    save! if persisted?
  end

  def track_changes(record)
    if record.changed?
      self.changed_fields = (changed_fields || []) | record.changed
      save! if persisted?
    end
  end

  # Class methods
  def self.batch_audit(records, service_name:, action: 'process', **options)
    # Handle both ActiveRecord relations and arrays
    records_enum = records.respond_to?(:find_each) ? records : records.to_a
    
    if records_enum.respond_to?(:find_each)
      records_enum.find_each do |record|
        process_audit_record(record, service_name, action, options) { |r, al| yield(r, al) }
      end
    else
      records_enum.each do |record|
        process_audit_record(record, service_name, action, options) { |r, al| yield(r, al) }
      end
    end
  end

  private_class_method def self.process_audit_record(record, service_name, action, options)
    audit_log = create!(
      auditable: record,
      service_name: service_name,
      action: action,
      **options
    )
    
    audit_log.mark_started!
    
    begin
      yield(record, audit_log)
      audit_log.mark_success! unless audit_log.status_success? || audit_log.status_failed?
    rescue StandardError => e
      audit_log.mark_failed!(e.message)
      raise
    end
  end

  def self.cleanup_old_logs(days_to_keep = 90)
    where('created_at < ?', days_to_keep.days.ago).delete_all
  end

  private

  # Callbacks
  before_create :set_defaults

  def set_defaults
    self.context ||= {}
    self.changed_fields ||= []
  end
end 