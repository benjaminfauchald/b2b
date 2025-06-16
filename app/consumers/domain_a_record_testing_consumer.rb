class DomainARecordTestingConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      process_message(message)
    end
  end

  private

  def process_message(message)
    return if processed?(message)
    
    payload = JSON.parse(message.payload)
    domain = Domain.find_by(domain: payload['domain'])
    
    return unless domain
    
    service = DomainARecordTestingService.new(domain: domain)
    result = service.call
    
    # Log the result
    audit_log = ServiceAuditLog.create!(
      auditable: domain,
      service_name: 'domain_a_record_testing',
      operation_type: 'test_a_record',
      status: result ? :success : :failed,
      columns_affected: ['www'],
      metadata: {
        domain_name: payload['domain'],
        result: result,
        consumer: self.class.name,
        kafka_topic: message.topic,
        kafka_partition: message.partition,
        kafka_offset: message.offset
      }
    )
    
    mark_as_processed(message)
  rescue JSON::ParserError => e
    Rails.logger.error "Invalid JSON in message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Error processing domain A record test: #{e.message}"
    raise
  end

  def processed?(message)
    ServiceAuditLog.exists?(
      service_name: 'domain_a_record_testing',
      message_id: message.offset
    )
  end

  def create_audit_log(domain)
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: 'domain_a_record_testing',
      operation_type: 'test_a_record',
      status: :pending,
      columns_affected: ['www'],
      metadata: { domain_name: domain.domain }
    )
  end

  def handle_error(error, message)
    Rails.logger.error(
      message: "Error processing A record test message",
      domain: message.payload,
      error: error.message,
      error_type: error.class.name
    )

    # Send to DLQ
    produce_message(
      topic: 'domain_a_record_testing_dlq',
      payload: message.payload,
      key: message.key
    )
  end
end 