# frozen_string_literal: true

class ConsumerTemplate < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      begin
        # Skip if already processed
        next if processed?(message.key)

        # Parse message
        data = JSON.parse(message.raw_payload)
        resource = find_resource(data)

        # Create audit log
        audit_log = ServiceAuditLog.create!(
          auditable: resource,
          service_name: self.class.name.underscore,
          operation_type: 'consume',
          status: :success,
          table_name: '<%= table_name %>',
          record_id: data['id'] || SecureRandom.uuid,
          columns_affected: [],
          metadata: {
            message_data: data,
            consumer: self.class.name,
            kafka_topic: message.topic,
            kafka_partition: message.partition,
            kafka_offset: message.offset
          }
        )

        audit_log.mark_started!

        # Process message
        result = process_message(resource, data)

        # Update audit log
        audit_log.mark_success!(
          'result' => result,
          'processing_time' => result[:duration]
        )

        # Mark as processed
        mark_as_processed(message.key)

      rescue StandardError => e
        audit_log&.mark_failed!(e.message)
        handle_error(e, message)
      end
    end
  end

  private

  def find_resource(data)
    # Implement resource lookup logic
    Resource.find(data['id'])
  end

  def process_message(resource, data)
    # Implement message processing logic
    {
      status: 'success',
      duration: 0.0
    }
  end

  def processed?(key)
    Rails.cache.read("processed:#{key}")
  end

  def mark_as_processed(key)
    Rails.cache.write("processed:#{key}", true, expires_in: 24.hours)
  end

  def handle_error(error, message)
    Rails.logger.error(
      "Error processing message: #{error.message}",
      error: error,
      message_key: message.key,
      consumer: self.class.name
    )

    # Send to DLQ if configured
    if dead_letter_topic
      produce_to_dlq(message, error)
    end
  end

  def dead_letter_topic
    ENV['KAFKA_DLQ_TOPIC']
  end

  def produce_to_dlq(message, error)
    payload = {
      original_message: message.raw_payload,
      error: error.message,
      timestamp: Time.current.iso8601
    }

    WaterDrop::SyncProducer.call(
      payload.to_json,
      topic: dead_letter_topic,
      key: message.key
    )
  rescue StandardError => e
    Rails.logger.error("Failed to produce to DLQ: #{e.message}")
  end
end 