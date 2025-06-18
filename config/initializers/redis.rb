require "redis"

redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
}

$redis = Redis.new(redis_config)

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
