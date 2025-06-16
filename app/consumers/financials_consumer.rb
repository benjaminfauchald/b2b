class FinancialsConsumer
  def initialize(group_id:, topic: 'company_financials')
    @group_id = group_id
    @topic = topic
    @logger = Rails.logger
  end
  
  def consume
    messages.each do |message|
      process_message(message)
    end
  end
  
  private
  
  def messages
    # This method should be implemented by the actual Kafka consumer
    # For testing purposes, it's mocked in the specs
    raise NotImplementedError, 'This method should be implemented by the actual Kafka consumer'
  end
  
  def process_message(message)
    start_time = Time.current
    payload = JSON.parse(message.value)
    
    log_to_sct('MESSAGE_RECEIVED', [], 'PROCESSING', 0, nil, {
      message_id: message.key,
      offset: message.offset,
      partition: message.partition,
      payload_keys: payload.keys
    })
    
    case payload['event_type']
    when 'company_financials_updated'
      handle_financials_updated(payload)
    else
      @logger.warn "Unknown event type: #{payload['event_type']}"
      log_to_sct('UNKNOWN_EVENT', [], 'WARNING', 0, "Unknown event type: #{payload['event_type']}", {
        message_id: message.key
      })
    end
    
    duration_ms = ((Time.current - start_time) * 1000).round
    log_to_sct('MESSAGE_PROCESSED', [], 'SUCCESS', duration_ms, nil, {
      message_id: message.key
    })
  rescue => e
    duration_ms = ((Time.current - start_time) * 1000).round
    log_to_sct('MESSAGE_ERROR', [], 'FAILED', duration_ms, e.message, {
      message_id: message.key,
      error_class: e.class.name,
      backtrace: e.backtrace.first(5)
    })
    raise # Re-raise to trigger Kafka's retry mechanism
  end
  
  def handle_financials_updated(payload)
    company = Company.find_by(registration_number: payload['registration_number'])
    unless company
      raise "Company not found: #{payload['registration_number']}"
    end
    
    # Update company with financial data only
    company.update!(
      ordinary_result: payload.dig('data', 'ordinary_result'),
      annual_result: payload.dig('data', 'annual_result'),
      operating_revenue: payload.dig('data', 'operating_revenue'),
      operating_costs: payload.dig('data', 'operating_costs')
    )
    
    # Log to SCT (ServiceAuditLog)
    ServiceAuditLog.create!(
      auditable: company,
      service_name: 'company_financials',
      action: 'update',
      status: :success,
      changed_fields: %w[ordinary_result annual_result operating_revenue operating_costs],
      context: payload['data'],
      completed_at: Time.current
    )
    
    log_to_sct('COMPANY_UPDATED', [], 'SUCCESS', 0, nil, {
      company_id: company.id,
      registration_number: company.registration_number
    })
  end
  
  def log_to_sct(action, fields, status, duration_ms, error_message = nil, metadata = {})
    begin
      # Replace with your actual SCT logging implementation
      Rails.logger.info("[SCT] #{action} - #{status} - #{error_message}")
      Rails.logger.debug("[SCT] Metadata: #{metadata.to_json}")
    rescue => e
      Rails.logger.error("Failed to log to SCT in consumer: #{e.message}")
    end
  end
end
