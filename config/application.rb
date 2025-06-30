require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module B2b
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks rubocop])
    
    # Add ViewComponents to autoload paths
    config.autoload_paths << Rails.root.join("app/components")
    config.eager_load_paths << Rails.root.join("app/components")

    # Configure Active Job to use Sidekiq
    config.active_job.queue_adapter = :sidekiq

    # Custom auditing flags
    config.service_auditing_enabled = true
    config.automatic_auditing_enabled = true

    # File upload configuration
    config.force_ssl = false
    config.max_request_size = 50.megabytes

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
