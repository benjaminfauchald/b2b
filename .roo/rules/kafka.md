---
description: 
globs: 
alwaysApply: false
---
## Karafka Configuration Reference (IMPORTANT)

**Current Syntax (Karafka 2.0+):**
```ruby
class KarafkaApp < Karafka::App
  setup do |config|
    config.client_id = 'my_application'
    
    # NEW: Use config.kafka hash with librdkafka options
    config.kafka = {
      'bootstrap.servers': 'localhost:9092',  # String, comma-separated
      'security.protocol': 'SASL_SSL',        # If needed
      'sasl.mechanisms': 'PLAIN'              # If needed
    }
  end
end

# DO NOT USE - This will cause NoMethodError in Karafka 2.0+
config.brokers = ['localhost:9092']

# Kafka Best Practices and Rules

## Message Deduplication
1. Always use message keys for deduplication:
   ```ruby
   # Producer
   produce_message(
     topic: 'topic_name',
     payload: data.to_json,
     key: "#{unique_id}:#{Time.current.beginning_of_hour.to_i}"
   )
   ```

2. Implement consumer-side deduplication:
   ```ruby
   # Consumer
   def consume
     messages.each do |message|
       next if processed?(message.key)
       # Process message
       mark_as_processed(message.key)
     end
   end
   ```

## Topic Configuration
1. Set appropriate retention period:
   ```ruby
   kafka.create_topic(
     topic,
     num_partitions: 3,
     replication_factor: 1,
     retention_ms: 7.days.to_i * 1000  # 7 days retention
   )
   ```

2. Configure partitions based on throughput:
   - Rule of thumb: 1 partition per 10MB/s throughput
   - Minimum 3 partitions for redundancy
   - Maximum 100 partitions per broker

## Producer Best Practices
1. Use synchronous production for critical messages:
   ```ruby
   WaterDrop::SyncProducer.call(payload, topic: topic)
   ```

2. Implement retry logic:
   ```ruby
   def produce_with_retry(topic:, payload:, max_retries: 3)
     retries = 0
     begin
       produce_message(topic: topic, payload: payload)
     rescue StandardError => e
       retries += 1
       retry if retries < max_retries
       raise
     end
   end
   ```

3. Batch messages when possible:
   ```ruby
   def batch_produce(topic:, messages:, batch_size: 1000)
     messages.each_slice(batch_size) do |batch|
       batch.each { |msg| produce_message(topic: topic, payload: msg) }
     end
   end
   ```

## Consumer Best Practices
1. Implement proper error handling:
   ```ruby
   def consume
     messages.each do |message|
       begin
         process_message(message)
       rescue StandardError => e
         handle_error(message, e)
       end
     end
   end
   ```

2. Use consumer groups for scalability:
   ```ruby
   # config/karafka.rb
   setup do |config|
     config.consumer_groups = [
       {
         name: 'domain_testing_group',
         topics: ['domain_testing']
       }
     ]
   end
   ```

3. Implement dead letter queues:
   ```ruby
   def handle_error(message, error)
     return if error.is_a?(TemporaryError)
     
     produce_message(
       topic: "#{message.topic}_dlq",
       payload: {
         original_message: message.raw_payload,
         error: error.message,
         timestamp: Time.current
       }.to_json
     )
   end
   ```

## Monitoring and Logging
1. Track consumer lag:
   ```ruby
   def monitor_consumer_lag
     lag = consumer.lag
     Rails.logger.info("Consumer lag: #{lag}")
     alert_if_lag_too_high(lag)
   end
   ```

2. Log important events:
   ```ruby
   def log_message_processing(message, status)
     Rails.logger.info(
       message_id: message.key,
       topic: message.topic,
       status: status,
       timestamp: Time.current
     )
   end
   ```

## Security
1. Use SSL/TLS for encryption:
   ```ruby
   # config/initializers/kafka.rb
   config.ssl_ca_cert = ENV['KAFKA_SSL_CA_CERT']
   config.ssl_client_cert = ENV['KAFKA_SSL_CLIENT_CERT']
   config.ssl_client_cert_key = ENV['KAFKA_SSL_CLIENT_CERT_KEY']
   ```

2. Implement authentication:
   ```ruby
   config.sasl_plain_username = ENV['KAFKA_USERNAME']
   config.sasl_plain_password = ENV['KAFKA_PASSWORD']
   ```

## Performance Optimization
1. Configure appropriate batch sizes:
   ```ruby
   config.producer.batch_size = 16_384  # 16KB
   config.producer.batch_linger_ms = 5  # 5ms
   ```

2. Set proper buffer sizes:
   ```ruby
   config.producer.buffer_memory = 32_768_000  # 32MB
   config.producer.compression_type = :snappy
   ```

## Error Recovery
1. Implement circuit breakers:
   ```ruby
   def with_circuit_breaker
     return if circuit_breaker.open?
     
     begin
       yield
       circuit_breaker.success
     rescue StandardError => e
       circuit_breaker.failure
       raise
     end
   end
   ```

2. Handle rebalancing:
   ```ruby
   def on_rebalance
     Rails.logger.info("Consumer group rebalancing")
     # Clean up resources
   end
   ```

## Testing
1. Use test topics:
   ```ruby
   # config/environments/test.rb
   config.kafka.test_mode = true
   config.kafka.test_topic_prefix = 'test_'
   ```

2. Mock Kafka in tests:
   ```ruby
   # spec/support/kafka_mock.rb
   class KafkaMock
     def produce_message(topic:, payload:, key: nil)
       # Mock implementation
     end
   end
   ```

## Deployment
1. Use environment variables:
   ```ruby
   # config/initializers/kafka.rb
   config.bootstrap_servers = ENV.fetch('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(',')
   ```

2. Configure health checks:
   ```ruby
   # config/initializers/health_check.rb
   HealthCheck.register('kafka') do
     kafka_client.healthy?
   end
   ```

Remember:
- Always use message keys for deduplication
- Implement proper error handling and retry logic
- Monitor consumer lag and performance
- Use appropriate security measures
- Test thoroughly before deployment
- Document all Kafka-related configurations
