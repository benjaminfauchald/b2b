# frozen_string_literal: true

return unless ENV["KAFKA_ENABLED"] == "true"

begin
  require "kafka"

  KAFKA_BROKERS = ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092").split(",")

  # Configure the Kafka client
  KAFKA_PRODUCER = Kafka.new(
    KAFKA_BROKERS,
    client_id: "b2b_services",
    ssl_ca_cert: ENV["KAFKA_SSL_CA_CERT"],
    ssl_client_cert: ENV["KAFKA_SSL_CLIENT_CERT"],
    ssl_client_cert_key: ENV["KAFKA_SSL_CLIENT_CERT_KEY"],
    ssl_verify_hostname: ENV["KAFKA_SSL_VERIFY_HOSTNAME"] != "false",
    logger: Rails.logger
  )

  # Create topics if they don't exist
  begin
    admin = KAFKA_PRODUCER.admin
    topics = [ "company_financials" ]

    existing_topics = admin.list_topics.map(&:name)
    topics_to_create = topics - existing_topics

    unless topics_to_create.empty?
      Rails.logger.info "Creating Kafka topics: #{topics_to_create.join(', ')}"
      admin.create_topics(
        topics_to_create.map { |topic| { topic: topic, num_partitions: 3, replication_factor: 1 } }
      )
    end
  rescue => e
    Rails.logger.error "Failed to create Kafka topics: #{e.message}"
  ensure
    admin&.close
  end

  Rails.logger.info "Kafka producer initialized successfully"
rescue LoadError => e
  Rails.logger.warn "Kafka gem not loaded: #{e.message}"
rescue => e
  Rails.logger.error "Failed to initialize Kafka: #{e.message}"
  raise e if Rails.env.development? || Rails.env.test?
end
