source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Authentication
gem "devise", "~> 4.9"
gem "omniauth", "~> 2.1"
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-github", "~> 2.0"
gem "omniauth-rails_csrf_protection", "~> 1.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

gem "redis", "~> 5.0"

# Pagination
gem "pagy", "~> 9.0"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mingw x64_mingw ]

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Test Framework
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"

  # Test Coverage
  gem "simplecov", require: false

  # Guard for automatic testing
  gem "guard-rspec"
  gem "guard-rubocop"
  gem "terminal-notifier-guard"

  # Environment variables
  gem "dotenv-rails"
end

# Background job processing

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end


group :development do
  gem "guard"
  gem "spring"
  gem "spring-watcher-listen"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Database cleanup for test isolation
  gem "database_cleaner-active_record"

  # Shoulda matchers for RSpec
  gem "shoulda-matchers", "~> 5.0"

  # HTTP request stubbing
  gem "webmock"
end

gem "rubocop", "~> 1.76", group: :development
gem "rubocop-rails", "~> 2.32", group: :development
gem "rubocop-performance", "~> 1.25", group: :development
gem "rubocop-rspec", "~> 3.6", groups: [:development, :test]
gem "tailwindcss-rails", "~> 4.2"
gem "view_component", "~> 3.0"

gem "sidekiq", "~> 8.0"

# Kafka
gem "ruby-kafka", "~> 1.5.0"  # Kafka client
gem "waterdrop", "~> 2.8.4"   # Kafka producer
gem "karafka", "~> 2.4.0"     # Kafka consumer framework
gem "dry-monitor"           # For monitoring Kafka operations

gem "httparty"              # For making HTTP requests
gem "nokogiri"              # For XML parsing
gem "json-schema", "~> 4.0"
gem "smarter_csv", "~> 1.8"  # CSV parsing and import functionality
gem "google-api-client"     # Google Custom Search API
gem "ruby-openai"           # OpenAI API for content validation
gem "firecrawl"             # Firecrawl API for web content extraction
gem "public_suffix", "~> 6.0"  # Domain name validation and parsing

# Email verification and validation
gem "truemail"        # Multi-layer email validation (syntax, DNS, SMTP)
gem "valid_email2"    # Disposable email detection + MX validation

# Web scraping and browser automation
gem "ferrum"          # Chrome DevTools Protocol for Ruby (Puppeteer alternative)

# Console enhancements for all environments
gem "pry-rails"
gem "awesome_print"
