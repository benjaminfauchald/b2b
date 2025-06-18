namespace :domain do
  desc "Run DomainTestingService for all applicable domains"
  task test_dns: :environment do
    puts "Starting domain DNS testing..."
    result = DomainTestingService.new.call

    puts "\nDomain DNS Testing Results:"
    puts "  Processed: #{result[:processed]} domains"
    puts "  Successful: #{result[:successful]} domains"
    puts "  Failed: #{result[:failed]} domains"
    puts "  Errors: #{result[:errors]} domains"

    # Show Kafka consumer lag
    begin
      kafka = Kafka.new(
        ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092").split(","),
        client_id: "b2b_services"
      )

      consumer_group = "domain_testing_consumer"
      topic = "domain_testing"

      lag = kafka.consumer_group_offsets(consumer_group)
      topic_lag = lag[topic]&.values&.sum || 0

      puts "\nKafka Status:"
      puts "  Consumer Lag: #{topic_lag} messages"
      puts "  Consumer Group: #{consumer_group}"
      puts "  Topic: #{topic}"
    rescue => e
      puts "\nError getting Kafka stats: #{e.message}"
    end
  end

  desc "Run DomainARecordTestingService for all applicable domains"
  task test_a_record: :environment do
    puts "Starting A record testing..."
    result = DomainARecordTestingService.new.call

    puts "\nA Record Testing Results:"
    puts "  Processed: #{result[:processed]} domains"
    puts "  Successful: #{result[:successful]} domains"
    puts "  Failed: #{result[:failed]} domains"
    puts "  Errors: #{result[:errors]} domains"

    # Show Kafka consumer lag
    begin
      kafka = Kafka.new(
        ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092").split(","),
        client_id: "b2b_services"
      )

      consumer_group = "domain_a_record_testing_consumer"
      topic = "domain_a_record_testing"

      lag = kafka.consumer_group_offsets(consumer_group)
      topic_lag = lag[topic]&.values&.sum || 0

      puts "\nKafka Status:"
      puts "  Consumer Lag: #{topic_lag} messages"
      puts "  Consumer Group: #{consumer_group}"
      puts "  Topic: #{topic}"
    rescue => e
      puts "\nError getting Kafka stats: #{e.message}"
    end
  end

  desc "Run DomainMxTestingService for domains with both DNS and WWW successful"
  task test_mx: :environment do
    puts "Starting MX record testing..."
    result = DomainMxTestingService.new.call

    puts "\nMX Record Testing Results:"
    puts "  Processed: #{result[:processed]} domains"
    puts "  Successful: #{result[:successful]} domains"
    puts "  Failed: #{result[:failed]} domains"
    puts "  Errors: #{result[:errors]} domains"

    # Show Kafka consumer lag
    begin
      kafka = Kafka.new(
        ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092").split(","),
        client_id: "b2b_services"
      )

      consumer_group = "domain_mx_testing_consumer"
      topic = "domain_mx_testing"

      lag = kafka.consumer_group_offsets(consumer_group)
      topic_lag = lag[topic]&.values&.sum || 0

      puts "\nKafka Status:"
      puts "  Consumer Lag: #{topic_lag} messages"
      puts "  Consumer Group: #{consumer_group}"
      puts "  Topic: #{topic}"
    rescue => e
      puts "\nError getting Kafka stats: #{e.message}"
    end
  end
end
