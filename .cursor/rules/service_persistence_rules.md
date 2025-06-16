# Service Persistence Rules

## Service Configuration

1. Create a systemd service file in `/etc/systemd/system/` with the following structure:
```ini
[Unit]
Description=Your Service Name
After=network.target

[Service]
Type=simple
User=benjamin
WorkingDirectory=/home/benjamin/b2b
Environment=RAILS_ENV=production
ExecStart=/usr/bin/bundle exec rails your:command
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Kafka Configuration (KRaft mode, no Zookeeper)

1. Kafka 4.x+ is installed via Docker and runs in KRaft (self-managed metadata) mode. No Zookeeper is required or used.

2. Create a `docker-compose.yml` file in your project root:
```yaml
version: '3'
services:
  kafka:
    image: bitnami/kafka:latest
    ports:
      - "9092:9092"
    environment:
      - KAFKA_CFG_NODE_ID=1
      - KAFKA_CFG_PROCESS_ROLES=broker,controller
      - KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka:9093
      - KAFKA_CFG_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      - KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=PLAINTEXT
      - KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true
      - KAFKA_CFG_DELETE_TOPIC_ENABLE=true
      - KAFKA_CFG_LOG_RETENTION_HOURS=168
      - KAFKA_CFG_LOG_RETENTION_CHECK_INTERVAL_MS=300000
      - KAFKA_CFG_OFFSETS_TOPIC_REPLICATION_FACTOR=1
      - KAFKA_CFG_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1
      - KAFKA_CFG_TRANSACTION_STATE_LOG_MIN_ISR=1
      - ALLOW_PLAINTEXT_LISTENER=yes
    volumes:
      - kafka_data:/bitnami/kafka
    restart: always

volumes:
  kafka_data:
    driver: local
```

3. Create a `config/kafka.yml` file with environment-specific settings:
```yaml
development:
  client_id: b2b_development
  seed_brokers: kafka://localhost:9092
  consumer:
    group_id: b2b_consumer_group
  producer:
    required_acks: 1
    max_retries: 3
    retry_backoff: 1000
  topics:
    domain_testing:
      partitions: 3
      replication_factor: 1
      retention: 7d
    domain_testing_dlq:
      partitions: 1
      replication_factor: 1
      retention: 14d

production:
  client_id: b2b_production
  seed_brokers: <%= ENV['KAFKA_BROKERS'] %>
  consumer:
    group_id: b2b_consumer_group
  producer:
    required_acks: -1
    max_retries: 5
    retry_backoff: 1000
  topics:
    domain_testing:
      partitions: 10
      replication_factor: 3
      retention: 7d
    domain_testing_dlq:
      partitions: 3
      replication_factor: 3
      retention: 14d
```

4. Start Kafka services:
```bash
# Start Kafka in KRaft mode
docker-compose up -d

# Verify services are running
docker-compose ps

# Create Kafka topics
rails kafka:create_topics
```

## Monitoring

1. Check service status:
```bash
# Check service status
sudo systemctl status your-service

# View service logs
sudo journalctl -u your-service -f

# Check Kafka status
docker-compose ps
docker-compose logs -f kafka
```

2. Monitor Kafka:
```bash
# View Kafka consumer groups
docker-compose exec kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# View consumer lag
docker-compose exec kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group b2b_consumer_group
```

## Service Management

1. Start/Stop services:
```bash
# Start services
sudo systemctl start your-service
docker-compose up -d

# Stop services
sudo systemctl stop your-service
docker-compose down

# Enable services on boot
sudo systemctl enable your-service
```

2. Best practices:
- Always use environment variables for sensitive data
- Implement proper error handling and logging
- Use consumer groups for message distribution
- Monitor consumer lag and system resources
- Implement dead letter queues for failed messages
- Use appropriate retention periods for topics
- Scale partitions based on expected load
- Implement proper security measures
- Regular backup of important data
- Monitor system resources and performance

## Security

1. Environment variables:
```bash
# .env file
KAFKA_BROKERS=kafka://localhost:9092
KAFKA_SSL_CA_CERT=/path/to/ca.pem
KAFKA_SSL_CLIENT_CERT=/path/to/client.pem
KAFKA_SSL_CLIENT_CERT_KEY=/path/to/client.key
```

2. SSL Configuration:
```yaml
# config/kafka.yml
production:
  ssl:
    ca_cert: <%= ENV['KAFKA_SSL_CA_CERT'] %>
    client_cert: <%= ENV['KAFKA_SSL_CLIENT_CERT'] %>
    client_cert_key: <%= ENV['KAFKA_SSL_CLIENT_CERT_KEY'] %>
```

## Maintenance

1. Regular tasks:
- Monitor disk usage
- Check log files
- Verify service health
- Update dependencies
- Backup configurations
- Review security settings
- Check system resources
- Monitor performance metrics
- Review error logs
- Update SSL certificates 