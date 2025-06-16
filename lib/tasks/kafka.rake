namespace :kafka do
  desc "Start Kafka consumer for domain testing"
  task start_consumer: :environment do
    puts "Starting Kafka consumer for domain testing..."
    Karafka::Server.start
  end

  desc "Create Kafka topics"
  task create_topics: :environment do
    require 'ruby-kafka'
    
    kafka = Kafka.new(
      ENV.fetch('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
      client_id: 'b2b_services'
    )

    topics = {
      'domain_testing' => {
        num_partitions: 3,
        replication_factor: 1,
        configs: {
          'retention.ms' => 7.days.to_i * 1000, # 7 days retention
          'cleanup.policy' => 'delete',
          'max.message.bytes' => 1_000_000, # 1MB max message size
          'compression.type' => 'snappy'
        }
      },
      'domain_testing_dlq' => { # Dead Letter Queue
        num_partitions: 1,
        replication_factor: 1,
        configs: {
          'retention.ms' => 30.days.to_i * 1000, # 30 days retention for DLQ
          'cleanup.policy' => 'delete'
        }
      },
      'company_financials' => {
        num_partitions: 3,
        replication_factor: 1,
        configs: {
          'retention.ms' => 30.days.to_i * 1000, # 30 days retention
          'cleanup.policy' => 'delete',
          'max.message.bytes' => 5_000_000, # 5MB max message size (larger financial data)
          'compression.type' => 'snappy',
          'message.timestamp.type' => 'LogAppendTime',
          'segment.bytes' => 100_000_000 # 100MB segments
        }
      },
      'company_financials_dlq' => { # Dead Letter Queue for financials
        num_partitions: 1,
        replication_factor: 1,
        configs: {
          'retention.ms' => 90.days.to_i * 1000, # 90 days retention for DLQ
          'cleanup.policy' => 'delete'
        }
      }
    }
    
    topics.each do |topic, config|
      begin
        kafka.create_topic(
          topic,
          num_partitions: config[:num_partitions],
          replication_factor: config[:replication_factor],
          config: config[:configs]
        )
        puts "Created topic: #{topic}"
      rescue Kafka::TopicAlreadyExists
        puts "Topic already exists: #{topic}"
      end
    end
  end
end 