require "redis"

# Redis database allocation:
# 0 - Rails cache store
# 1 - Sidekiq job queues
# 2 - Application-specific data (if needed)

# Cache store Redis (database 0)
cache_redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
}

# Sidekiq Redis (database 1)
sidekiq_redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
}

# Global Redis instance for application use (database 2)
app_redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/2"),
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
}

$redis = Redis.new(app_redis_config)

Sidekiq.configure_server do |config|
  config.redis = sidekiq_redis_config
end

Sidekiq.configure_client do |config|
  config.redis = sidekiq_redis_config
end
