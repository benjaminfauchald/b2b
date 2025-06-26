# Redis Configuration

This application uses Redis for persistent caching and job queues across all environments.

## Database Allocation

Redis databases are separated by purpose:

- **Database 0**: Rails cache store (`ActiveSupport::Cache::RedisCacheStore`)
- **Database 1**: Sidekiq job queues 
- **Database 2**: Application-specific data (available via `$redis` global)

## Environment Configuration

### Development
- **Cache**: Redis cache store (when caching enabled via `rails dev:cache`)
- **Jobs**: Sidekiq with Redis
- **URL**: `redis://localhost:6379/[db_number]`

### Production  
- **Cache**: Redis cache store with compression and namespacing
- **Jobs**: Sidekiq with Redis
- **URL**: Set via `REDIS_URL` environment variable

## Configuration Files

- `config/initializers/redis.rb` - Redis connection setup
- `config/environments/development.rb` - Development cache configuration
- `config/environments/production.rb` - Production cache configuration

## Benefits

✅ **Persistent Caching**: Cache survives application restarts
✅ **Shared Caching**: Multiple app instances can share cache
✅ **High Performance**: Redis is significantly faster than database caching
✅ **Scalability**: Can easily scale to Redis clusters
✅ **Separation**: Different Redis databases prevent data conflicts

## Commands

```bash
# Enable caching in development
rails dev:cache

# Test cache in console
Rails.cache.write('test', 'value')
Rails.cache.read('test')

# Access application Redis instance
$redis.ping
$redis.set('key', 'value')
$redis.get('key')
```

## Production Setup

Set the `REDIS_URL` environment variable:

```bash
export REDIS_URL="redis://your-redis-host:6379/0"
```

For Redis with authentication:
```bash
export REDIS_URL="redis://username:password@your-redis-host:6379/0"
```