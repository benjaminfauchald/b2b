require "sidekiq"
require "sidekiq/web"

# Load Rails environment to ensure proper configuration
require_relative "../config/environment"

# Configure Sidekiq Web UI
Sidekiq::Web.use Rack::Session::Cookie, secret: Rails.application.secret_key_base, same_site: true, max_age: 86400

# Run the Sidekiq Web UI
run Sidekiq::Web
