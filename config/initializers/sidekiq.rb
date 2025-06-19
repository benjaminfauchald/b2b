require "sidekiq"

redis_config = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

Sidekiq.configure_server do |config|
  config.redis = redis_config
  config.concurrency = 5

  # Set default queue weights - queues is an array of [queue_name, weight] pairs
  config.queues = (config.queues || []).map { |queue_config|
    queue_config.is_a?(Array) ? queue_config : [ queue_config, 5 ]
  }
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
