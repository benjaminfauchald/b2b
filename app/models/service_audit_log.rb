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

  def mark_completed!(duration_ms: nil)
    now = Time.current
    update!(
      completed_at: now,
      duration_ms: duration_ms,
      status: :success
    )
  end

  def mark_success!(context_data = {})
    add_context(context_data) if context_data.present?
    now = Time.current
    duration = started_at ? ((now - started_at) * 1000).to_i : nil
    mark_completed!(duration_ms: duration)
    update!(status: :success)
  end

  def mark_failed!(error = nil, context_data = {})
    add_context(context_data) if context_data.present?
    now = Time.current
    
    # Handle frozen string errors by creating a new string
    error_message = if error.is_a?(String)
                      error.dup.force_encoding('UTF-8')
                    elsif error.respond_to?(:message)
                      error.message.to_s.dup.force_encoding('UTF-8')
                    else
                      error.to_s.dup.force_encoding('UTF-8')
                    end
    
    update!(
      completed_at: now,
      status: :failed,
      error_message: error_message
    )
  end

  def add_context(key_or_hash, value = nil)
    current_context = context || {}
    
    # Create a new hash with stringified keys and properly encoded values
    new_context = if key_or_hash.is_a?(Hash)
                    key_or_hash.each_with_object({}) do |(k, v), hash|
                      hash[k.to_s] = deep_encode_value(v)
                    end
                  else
                    { key_or_hash.to_s => deep_encode_value(value) }
                  end
    
    update!(context: current_context.merge(new_context))
  end
  
  private
  
  def deep_encode_value(value)
    case value
    when String
      value.dup.force_encoding('UTF-8')
    when Hash
      value.transform_values { |v| deep_encode_value(v) }
    when Array
      value.map { |v| deep_encode_value(v) }
    else
      value
    end
  rescue => e
    Rails.logger.error("Failed to encode value: #{value.inspect}. Error: #{e.message}")
    value.to_s.dup.force_encoding('UTF-8') rescue value
  end

  def track_changes(record)
    if record.changed?
      self.changed_fields = (changed_fields || []) | record.changed
      save! if persisted?
    end
  end

  # Class methods
  def self.batch_audit(records, service_name:, action: 'process', batch_size: 1000, **options)
    records.each_slice(batch_size) do |batch|
      batch.each do |record|
        audit_log = create!(
          auditable: record,
          service_name: service_name,
          action: action,
          **options
        )
        
        begin
          yield(record, audit_log)
        rescue StandardError => e
          audit_log.mark_failed!(e)
          raise
        end
      end
    end
  end

  def self.cleanup_old_logs(days)
    where('created_at < ?', days.days.ago).delete_all
  end

  # Callbacks
  before_create :set_defaults

  def set_defaults
    self.context ||= {}
    self.changed_fields ||= []
  end
end 