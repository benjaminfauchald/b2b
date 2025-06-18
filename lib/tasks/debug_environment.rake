namespace :debug do
  desc "Debug Rails environment and configuration"
  task env: :environment do
    puts "\n" + "="*80
    puts "🔍 RAILS ENVIRONMENT DEBUG REPORT"
    puts "="*80
    puts "Timestamp: #{Time.current}"
    puts "User: #{ENV['USER'] || 'unknown'}"
    puts "PWD: #{Dir.pwd}"
    puts "="*80

    # Basic Rails environment
    puts "\n📋 RAILS ENVIRONMENT:"
    puts "Rails.env: #{Rails.env}"
    puts "Rails.version: #{Rails.version}"
    puts "Ruby version: #{RUBY_VERSION}"
    puts "Ruby platform: #{RUBY_PLATFORM}"

    # Environment variables
    puts "\n🔧 ENVIRONMENT VARIABLES:"
    env_vars = %w[
      RAILS_ENV
      RACK_ENV
      RAILS_MASTER_KEY
      SECRET_KEY_BASE
      DATABASE_URL
      REDIS_URL
      KAFKA_ENABLED
      PGHOST
      PGPORT
      PGDATABASE
      PGUSER
      PGPASSWORD
      POSTGRES_HOST
      POSTGRES_PORT
      POSTGRES_DB
      POSTGRES_USER
      POSTGRES_PASSWORD
      MAIL_USERNAME
      MAIL_PASSWORD
      SMTP_HOST
      SMTP_PORT
      SMTP_DOMAIN
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      AWS_REGION
      S3_BUCKET
      SIDEKIQ_USERNAME
      SIDEKIQ_PASSWORD
      BASIC_AUTH_USERNAME
      BASIC_AUTH_PASSWORD
      SENTRY_DSN
      NEW_RELIC_LICENSE_KEY
      SSL_CERT_PATH
      SSL_KEY_PATH
    ]

    env_vars.each do |var|
      value = ENV[var]
      if value
        # Mask sensitive values
        if var.include?("KEY") || var.include?("SECRET") || var.include?("PASSWORD")
          puts "#{var}: #{value[0..10]}... (masked)"
        else
          puts "#{var}: #{value}"
        end
      else
        puts "#{var}: NOT SET"
      end
    end

    # All environment variables (first few chars only)
    puts "\n📊 ALL ENVIRONMENT VARIABLES (first 20 chars):"
    ENV.keys.sort.each do |key|
      value = ENV[key] || ""
      display_value = value.length > 20 ? "#{value[0..20]}..." : value
      puts "#{key}: #{display_value}"
    end

    # Rails configuration paths
    puts "\n📂 RAILS PATHS:"
    puts "Rails.root: #{Rails.root}"
    puts "Rails.application.config.root: #{Rails.application.config.root}"
    # puts "Config path: #{Rails.application.config.config_for}" # Not available in Rails 8

    # Credentials investigation
    puts "\n🔐 CREDENTIALS DEBUG:"
    begin
      puts "Rails.application.credentials methods: #{Rails.application.credentials.methods.grep(/secret/).sort}"
      puts "Rails.application.config.secret_key_base present: #{Rails.application.config.secret_key_base.present?}"

      # Try to access credentials
      secret_key = Rails.application.credentials.secret_key_base
      puts "Credentials secret_key_base present: #{secret_key.present?}"

      if Rails.application.credentials.respond_to?(:database)
        puts "Database credentials accessible: true"
      end

    rescue => e
      puts "❌ Error accessing credentials: #{e.class}: #{e.message}"
      puts "Backtrace: #{e.backtrace.first(3).join('\n')}"
    end

    # File system checks
    puts "\n📁 FILE SYSTEM CHECKS:"
    files_to_check = [
      "config/credentials.yml.enc",
      "config/master.key",
      "config/credentials/production.yml.enc",
      "config/credentials/production.key",
      ".env",
      "tmp/restart.txt"
    ]

    files_to_check.each do |file|
      full_path = Rails.root.join(file)
      if File.exist?(full_path)
        stat = File.stat(full_path)
        puts "✅ #{file}: exists (size: #{stat.size} bytes, modified: #{stat.mtime})"
      else
        puts "❌ #{file}: missing"
      end
    end

    # Database connection
    puts "\n🗄️  DATABASE CONNECTION:"
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      puts "✅ Database connection: OK"
      puts "Database adapter: #{ActiveRecord::Base.connection.adapter_name}"
      puts "Database name: #{ActiveRecord::Base.connection.current_database}"
    rescue => e
      puts "❌ Database connection failed: #{e.message}"
    end

    # Redis connection
    puts "\n🔴 REDIS CONNECTION:"
    begin
      if defined?(Redis)
        redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/0")
        redis.ping
        puts "✅ Redis connection: OK"
        puts "Redis info: #{redis.info('server')['redis_version']}"
      else
        puts "⚠️  Redis gem not loaded"
      end
    rescue => e
      puts "❌ Redis connection failed: #{e.message}"
    end

    # Load paths and gems
    puts "\n💎 GEM ENVIRONMENT:"
    puts "Bundler.bundle_path: #{Bundler.bundle_path}" if defined?(Bundler)
    puts "Gem.path: #{Gem.path.first}"
    puts "$LOAD_PATH entries: #{$LOAD_PATH.size}"

    # Rails application configuration
    puts "\n⚙️  RAILS APPLICATION CONFIG:"
    config = Rails.application.config

    config_items = %w[
      eager_load
      cache_classes
      consider_all_requests_local
      action_dispatch.show_exceptions
      serve_static_files
      force_ssl
      log_level
    ]

    config_items.each do |item|
      begin
        value = item.split(".").reduce(config) { |obj, method| obj.send(method) }
        puts "#{item}: #{value}"
      rescue => e
        puts "#{item}: ERROR - #{e.message}"
      end
    end

    # Custom application settings
    puts "\n🏗️  CUSTOM APPLICATION SETTINGS:"
    begin
      if Rails.application.config.respond_to?(:service_auditing_enabled)
        puts "service_auditing_enabled: #{Rails.application.config.service_auditing_enabled}"
      end

      if Rails.application.config.respond_to?(:automatic_auditing_enabled)
        puts "automatic_auditing_enabled: #{Rails.application.config.automatic_auditing_enabled}"
      end
    rescue => e
      puts "Error checking custom settings: #{e.message}"
    end

    puts "\n" + "="*80
    puts "🎯 DEBUG REPORT COMPLETED"
    puts "="*80
  end

  desc "Test credentials loading specifically"
  task credentials: :environment do
    puts "\n🔐 DETAILED CREDENTIALS DEBUG:"

    # Check master key
    master_key_path = Rails.root.join("config/master.key")
    puts "Master key file exists: #{File.exist?(master_key_path)}"

    if File.exist?(master_key_path)
      key_content = File.read(master_key_path).strip
      puts "Master key length: #{key_content.length}"
      puts "Master key format: #{key_content.match?(/\A[a-f0-9]{64}\z/) ? 'valid hex' : 'invalid format'}"
    end

    # Check credentials file
    creds_path = Rails.root.join("config/credentials.yml.enc")
    puts "Credentials file exists: #{File.exist?(creds_path)}"

    if File.exist?(creds_path)
      puts "Credentials file size: #{File.size(creds_path)} bytes"
    end

    # Try manual decryption
    begin
      puts "Attempting manual credentials access..."
      creds = Rails.application.credentials
      puts "Credentials class: #{creds.class}"
      puts "Credentials responds to secret_key_base: #{creds.respond_to?(:secret_key_base)}"

      # Try to get the secret key
      secret_key = creds.secret_key_base
      puts "Secret key base present: #{secret_key.present?}"
      puts "Secret key base length: #{secret_key&.length || 0}"

    rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
      puts "❌ InvalidMessage error: #{e.message}"
      puts "This means the master key doesn't match the credentials file"

    rescue => e
      puts "❌ Other error: #{e.class}: #{e.message}"
    end

    # Environment-specific credentials
    puts "\nChecking environment-specific credentials..."
    env_creds_path = Rails.root.join("config/credentials/#{Rails.env}.yml.enc")
    env_key_path = Rails.root.join("config/credentials/#{Rails.env}.key")

    puts "Environment credentials file exists: #{File.exist?(env_creds_path)}"
    puts "Environment key file exists: #{File.exist?(env_key_path)}"
  end
end
