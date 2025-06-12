class ApplicationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  # Core service attributes
  attribute :service_name, :string
  attribute :action, :string, default: 'process'
  attribute :batch_size, :integer

  # Validations
  validates :service_name, presence: true, format: {
    with: /\A[a-z_]+_v\d+\z/,
    message: 'must follow naming convention (service_name_v1)'
  }

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

  # Batch processing with audit logging
  def batch_process(records, **options)
    effective_batch_size = batch_size || configuration&.batch_size
    
    # Filter out service-specific options that shouldn't go to audit log
    audit_options = options.except(:batch_size)
    
    ServiceAuditLog.batch_audit(
      records, 
      service_name: service_name, 
      action: action,
      **audit_options
    ) do |record, audit_log|
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