class ApplicationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  include FeatureMemoryIntegration if defined?(FeatureMemoryIntegration)

  attr_reader :service_name, :action, :batch_size

  # Core service attributes
  attribute :action, :string, default: "process"
  attribute :batch_size, :integer

  # Validations
  validates :action, presence: true, format: {
    with: /\A[a-z0-9_]+\z/,
    message: "must follow naming convention (e.g., process, enhance, test)"
  }

  validates :service_name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: "can only contain lowercase letters, numbers, and underscores" }

  def initialize(service_name:, action: "process", batch_size: 1000, **attributes)
    # Initialize ActiveModel::Attributes
    @attributes = {}

    @service_name = service_name
    @action = action
    @batch_size = batch_size
    attributes.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  # Main entry point
  def call
    validate!
    validate_sct_compliance!
    log_service_start

    begin
      result = perform
      log_service_completion(result)
      result
    rescue StandardError => e
      log_service_error(e)
      raise
    end
  end

  # Validation helper
  def validate!
    raise ActiveModel::ValidationError, self unless valid?
  end

  # SCT Pattern compliance validation
  def validate_sct_compliance!
    errors = []

    # Check required methods exist
    errors << "Service must implement #perform method" unless respond_to?(:perform, true)
    errors << "Service must implement #service_active? method" unless respond_to?(:service_active?, true)
    errors << "Service must implement #success_result method" unless respond_to?(:success_result, true)
    errors << "Service must implement #error_result method" unless respond_to?(:error_result, true)

    # Check service configuration exists
    if service_name.present?
      config = ServiceConfiguration.find_by(service_name: service_name)
      unless config
        Rails.logger.warn "SCT Warning: Service '#{service_name}' has no ServiceConfiguration record"
      end
    end

    # Check for audit_service_operation usage (this is a warning, not an error)
    if respond_to?(:audit_service_operation, true)
      Rails.logger.debug "SCT: Service '#{service_name}' implements audit_service_operation ✓"
    else
      Rails.logger.warn "SCT Warning: Service '#{service_name}' should implement audit_service_operation for proper audit tracking"
    end

    if errors.any?
      raise StandardError, "SCT Compliance Errors: #{errors.join(', ')}"
    end
  end

  # Configuration access
  def configuration
    @configuration ||= ServiceConfiguration.find_by(service_name: service_name)
  end

  # Service name derived from class name
  def service_name
    return @service_name if @service_name.present?
    if self.class.name.present? && self.class.name != ""
      self.class.name.underscore.encode("UTF-8")
    else
      # Fallback for anonymous classes in tests
      "test_service_#{SecureRandom.hex(8)}"
    end
  end

  def service_name=(value)
    @service_name = value
  end

  # Batch processing with audit logging
  def batch_process(records)
    ServiceAuditLog.batch_audit(records, service_name: service_name, operation_type: action, batch_size: batch_size) do |record, audit_log|
      yield(record, audit_log)
    end
  end

  # Class method for convenience
  def self.call(**attributes)
    new(**attributes).call
  end

  protected

  # Abstract method - must be implemented by subclasses
  def perform
    raise NotImplementedError, "#{self.class.name} must implement #perform"
  end

  # Logging methods
  def log_service_start
    Rails.logger.info "Starting service: #{service_name} (action: #{action})"
  end

  def log_service_completion(result = nil)
    result_info = result.respond_to?(:class) ? result.class.name : result.to_s
    Rails.logger.info "Completed service: #{service_name} (action: #{action}) - Result: #{result_info}"
  end

  def log_service_error(error, context = {})
    error_message = error.respond_to?(:message) ? error.message : error.to_s
    error_class = error.respond_to?(:class) ? error.class.name : "UnknownError"
    context_str = context.any? ? " - Context: #{context.inspect}" : ""
    Rails.logger.error "Service failed: #{service_name} (action: #{action}) - Error: #{error_class}: #{error_message}#{context_str}"
  end

  # Alias for backward compatibility
  alias_method :log_start, :log_service_start
  alias_method :log_completion, :log_service_completion
  alias_method :log_error, :log_service_error

  # Audit logging for service operations
  def audit_service_operation(auditable = nil)
    # Services don't have saved_changes - that's an ActiveRecord feature
    columns = [ "none" ]

    metadata_value = { error: "no metadata" }
    if defined?(context) && context.present?
      metadata_value = context
    end

    audit_log = ServiceAuditLog.create!(
      auditable: auditable,
      service_name: service_name,
      operation_type: action,
      status: :pending,
      columns_affected: columns,
      metadata: metadata_value,
      table_name: auditable ? auditable.class.table_name : "unknown",
      record_id: auditable ? auditable.id.to_s : "unknown",
      started_at: Time.current
    )

    begin
      result = yield(audit_log)

      # Don't overwrite metadata, just mark as success and calculate execution time
      audit_log.update!(
        status: :success,
        completed_at: Time.current,
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
      )

      result
    rescue StandardError => e
      # Check if this is a rate limit error with retry_after
      metadata = { "error" => e.message }
      status = :failed

      if e.message.include?("rate limit") && e.respond_to?(:retry_after)
        metadata["rate_limited"] = true
        metadata["retry_after"] = e.retry_after
        status = :rate_limited
      end

      # Use update_columns to bypass validations and set the status directly
      audit_log.update_columns(
        status: status,
        error_message: e.message,
        completed_at: Time.current,
        metadata: audit_log.metadata.merge(metadata),
        execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
      )

      raise e
    end
  end
end
