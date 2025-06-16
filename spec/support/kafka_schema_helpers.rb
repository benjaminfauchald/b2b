# frozen_string_literal: true

require 'json-schema'

module KafkaSchemaHelpers
  def load_kafka_schema(topic)
    path = Rails.root.join('docs', 'event_schemas', "#{topic}.json")
    JSON.parse(File.read(path))
  end

  def validate_kafka_message!(topic, message)
    schema = load_kafka_schema(topic)
    valid = JSON::Validator.validate(schema, message)
    expect(valid).to be(true), "Message does not match schema for #{topic}: #{message.inspect}"
  end
end

RSpec.configure do |config|
  config.include KafkaSchemaHelpers
end 