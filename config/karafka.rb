# frozen_string_literal: true

require 'yaml'
require 'karafka'

# Load Kafka configuration
KAFKA_CONFIG = YAML.load_file(Rails.root.join('config', 'kafka.yml'))[Rails.env]

# Configure Karafka app
class KarafkaApp < Karafka::App
  setup do |config|
    # Set client ID from consumer group ID
    config.client_id = KAFKA_CONFIG['consumer']['group_id']

    # Set bootstrap servers
    bootstrap_servers = KAFKA_CONFIG['kafka']['seed_brokers'].map { |broker| broker.gsub('kafka://', '') }.join(',')
    
    # Configure all Kafka settings (consumer + producer)
    config.kafka = {
      # Bootstrap servers
      'bootstrap.servers': bootstrap_servers,
      
      # Producer settings
      'acks': KAFKA_CONFIG['producer']['required_acks'],
      'retries': KAFKA_CONFIG['producer']['max_retries'],
      'retry.backoff.ms': KAFKA_CONFIG['producer']['retry_backoff'],
      
      # Consumer settings
      'auto.offset.reset': 'earliest',
      'enable.auto.commit': false
    }

    # Monitor app initialization
    config.monitor.subscribe('app.initialized') do
      Rails.logger.info('Karafka app initialized')
    end

    config.client_id = 'b2b'
    config.consumer_persistence = true
  end

  routes.draw do
    consumer_group KAFKA_CONFIG['consumer']['group_id'] do
      # Domain testing topics
      topic 'domain_testing' do
        consumer DomainTestingConsumer
      end

      topic 'domain_a_record_testing' do
        consumer DomainARecordTestingConsumer
      end
      
      # Financials topics
      topic 'company_financials' do
        consumer FinancialsConsumer
        dead_letter_queue(
          topic: 'company_financials_dlq',
          max_retries: 3
        )
        manual_offset_commits false
        start_from_beginning Rails.env.development?
      end

      topic 'domain_mx_testing' do
        consumer DomainMXTestingConsumer
      end

      topic 'brreg_migration' do
        consumer BrregMigrationConsumer
      end
    end
  end
end

# Load consumers
require Rails.root.join('app', 'consumers', 'domain_testing_consumer')
require Rails.root.join('app', 'consumers', 'domain_a_record_testing_consumer')
require Rails.root.join('app', 'consumers', 'domain_mx_testing_consumer')
require Rails.root.join('app', 'consumers', 'brreg_migration_consumer') 