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
    
    create_audit_log(domain)
    mark_as_processed(message)
  rescue StandardError => e
    handle_error(e, message)
  end

  def processed?(message)
    ServiceAuditLog.exists?(
      service_name: 'domain_a_record_testing_service',
      message_id: message.offset
    )
  end

  def create_audit_log(domain)
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: 'domain_a_record_testing_service',
      action: 'test_a_record',
      status: :success,
      context: {
        domain_name: domain.domain,
        message_id: message.offset
      }
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