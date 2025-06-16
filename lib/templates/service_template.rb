# frozen_string_literal: true

class ServiceTemplate < KafkaService
  attr_reader :resource, :batch_size, :max_retries

  def initialize(resource:, batch_size: 1000, max_retries: 3)
    @resource = resource
    @batch_size = batch_size
    @max_retries = max_retries
  end

  def call
    process_with_retry do
      # Implement your service logic here
      result = process_resource
      
      # Create audit log
      audit_log = ServiceAuditLog.create!(
        auditable: resource,
        service_name: self.class.name.underscore,
        operation_type: 'process',
        status: :pending,
        columns_affected: [],
        metadata: { resource_id: resource.id }
      )
      
      audit_log.mark_started!
      
      # Process the resource
      result = process_resource
      
      # Update audit log
      audit_log.mark_success!(
        'result' => result,
        'processing_time' => result[:duration]
      )

      result
    end
  end

  def self.process_in_batches(resources)
    resources.find_each(batch_size: 1000) do |resource|
      new(resource: resource).call
    end
  end

  private

  def process_with_retry
    retries = 0
    begin
      yield
    rescue StandardError => e
      retries += 1
      if retries <= max_retries
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        handle_error(e)
        raise
      end
    end
  end

  def process_resource
    # Implement your resource processing logic here
    {
      status: 'success',
      duration: 0.0
    }
  end

  def handle_error(error)
    Rails.logger.error(
      "Error processing #{resource.class.name} #{resource.id}: #{error.message}",
      error: error,
      resource_id: resource.id,
      service: self.class.name
    )
  end

  def produce_message(topic:, payload:, key: nil)
    WaterDrop::SyncProducer.call(
      payload,
      topic: topic,
      key: key,
      partition_key: key
    )
  rescue StandardError => e
    Rails.logger.error("Failed to produce message to #{topic}: #{e.message}")
    raise
  end
end 