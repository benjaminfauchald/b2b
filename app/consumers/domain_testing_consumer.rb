class DomainTestingConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      process_message(message)
    end
  end

  private

  def process_message(message)
    # Skip if already processed
    return if processed?(message)

    # Parse payload
    payload = JSON.parse(message.payload)
    domain = payload['domain']

    # Create audit log
    create_audit_log(domain)

    # Mark as processed
    mark_as_processed(message)
  rescue StandardError => e
    handle_error(e, message)
  end

  def processed?(message)
    Rails.cache.exist?("processed_domain:#{message.key}")
  end

  def create_audit_log(domain)
    DomainAuditLog.create!(
      domain: domain,
      status: 'processed',
      processed_at: Time.current
    )
  end

  def mark_as_processed(message)
    Rails.cache.write("processed_domain:#{message.key}", true, expires_in: 1.day)
  end

  def handle_error(error, message)
    Rails.logger.error("Error processing domain: #{error.message}")
    
    # Send to dead letter queue
    produce_message(
      topic: 'domain_testing_dlq',
      payload: {
        original_message: message.payload,
        error: error.message,
        timestamp: Time.current
      }.to_json,
      key: message.key
    )
  end
end 