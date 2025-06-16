class ApplicationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attr_reader :service_name, :action, :batch_size

  # Core service attributes
  attribute :action, :string, default: 'process'
  attribute :batch_size, :integer

  # Validations
  validates :action, presence: true, format: {
    with: /\A[a-z0-9_]+\z/,
    message: 'must follow naming convention (e.g., process, enhance, test)'
  }

  validates :service_name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: "can only contain lowercase letters, numbers, and underscores" }

  def initialize(service_name:, action: 'process', batch_size: 1000, **attributes)
    @service_name = service_name
    @action = action
    @batch_size = batch_size
    attributes.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  # Main entry point
  def call
    validate!
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

  # Configuration access
  def configuration
    @configuration ||= ServiceConfiguration.find_by(service_name: service_name)
  end

  # Service name derived from class name
  def service_name
    return @service_name if @service_name.present?
    if self.class.name.present? && self.class.name != ""
      self.class.name.underscore.encode('UTF-8')
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
    ServiceAuditLog.batch_audit(records, service_name: service_name, action: action, batch_size: batch_size) do |record, audit_log|
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

  def log_service_completion(result)
    Rails.logger.info "Completed service: #{service_name} (action: #{action}) - Result: #{result.class.name}"
  end

  def log_service_error(error)
    Rails.logger.error "Service failed: #{service_name} (action: #{action}) - Error: #{error.class.name}: #{error.message}"
  end
end 