require 'json-schema'

class KafkaService < ApplicationService
  class << self
    def topic_name
      name.underscore
    end

    def schema_path
      Rails.root.join('docs', 'event_schemas', "#{topic_name}.json")
    end

    def schema
      @schema ||= File.exist?(schema_path) ? JSON.parse(File.read(schema_path)) : nil
    end

    def produce(message, key: nil)
      if schema
        unless JSON::Validator.validate(schema, message)
          error_msg = "Invalid message schema for #{topic_name}: #{message.inspect}"
          Rails.logger.error(error_msg)
          raise error_msg
        end
      end
      WaterDrop::SyncProducer.call(
        message.to_json,
        topic: topic_name,
        key: key
      )
    end

    def call(*args)
      new(*args).call
    end
  end

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

  def produce_message(topic:, payload:, key: nil)
    Karafka.producer.produce_sync(
      topic: topic,
      payload: payload,
      key: key
    )
  end

  def produce_message_with_retry(topic:, payload:, key: nil, max_retries: 3)
    retries = 0
    begin
      produce_message(topic: topic, payload: payload, key: key)
    rescue StandardError => e
      retries += 1
      if retries <= max_retries
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        Rails.logger.error("Failed to produce message after #{max_retries} retries: #{e.message}")
        raise
      end
    end
  end

  protected

  def perform
    raise NotImplementedError, "#{self.class.name} must implement #perform"
  end
end 