namespace :setup do
  desc "Setup production environment configuration"
  task production: :environment do
    puts "🔧 Setting up production environment..."

    # Generate new master key if current one is invalid
    master_key_path = Rails.root.join("config/master.key")

    if File.exist?(master_key_path)
      current_key = File.read(master_key_path).strip
      if current_key.length != 64 || !current_key.match?(/\A[a-f0-9]{64}\z/)
        puts "⚠️  Current master key is invalid (length: #{current_key.length})"
        puts "Generating new master key..."

        # Backup old files
        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        FileUtils.cp(master_key_path, "#{master_key_path}.backup_#{timestamp}") if File.exist?(master_key_path)

        creds_path = Rails.root.join("config/credentials.yml.enc")
        FileUtils.cp(creds_path, "#{creds_path}.backup_#{timestamp}") if File.exist?(creds_path)

        # Generate new master key
        new_key = SecureRandom.hex(32)
        File.write(master_key_path, new_key)
        puts "✅ New master key generated: #{new_key[0..10]}..."

        # Remove old credentials file so it can be recreated
        File.delete(creds_path) if File.exist?(creds_path)
        puts "🗑️  Removed old credentials file"
      else
        puts "✅ Master key format is valid"
      end
    else
      puts "❌ Master key file missing, generating new one..."
      new_key = SecureRandom.hex(32)
      File.write(master_key_path, new_key)
      puts "✅ New master key generated"
    end

    # Create production credentials with required keys
    puts "\n📝 Setting up production credentials..."

    # Read the master key
    master_key = File.read(master_key_path).strip

    # Create credentials content
    credentials_content = {
      secret_key_base: SecureRandom.hex(64),
      database: {
        host: "app.connectica.no",
        port: 5432,
        database: "b2b_production",
        username: "benjamin",
        password: "Charcoal2020!"
      },
      redis: {
        url: "redis://localhost:6379/0"
      }
    }.to_yaml

    # Encrypt and save credentials
    creds_path = Rails.root.join("config/credentials.yml.enc")
    encryptor = ActiveSupport::MessageEncryptor.new([ master_key ].pack("H*"))
    encrypted_content = encryptor.encrypt_and_sign(credentials_content)
    File.write(creds_path, encrypted_content)

    puts "✅ Production credentials created"

    # Create comprehensive .env file with all production variables
    env_content = <<~ENV
      # Rails Environment
      RAILS_ENV=production
      RACK_ENV=production
      RAILS_MASTER_KEY=#{master_key}
      SECRET_KEY_BASE=#{SecureRandom.hex(64)}

      # Database Configuration (PostgreSQL)
      DATABASE_URL=postgresql://benjamin:Charcoal2020!@app.connectica.no:5432/b2b_production
      PGHOST=app.connectica.no
      PGPORT=5432
      PGDATABASE=b2b_production
      PGUSER=benjamin
      PGPASSWORD=Charcoal2020!

      # Alternative PostgreSQL variables (for different libraries)
      POSTGRES_HOST=app.connectica.no
      POSTGRES_PORT=5432
      POSTGRES_DB=b2b_production
      POSTGRES_USER=benjamin
      POSTGRES_PASSWORD=Charcoal2020!

      # Redis Configuration
      REDIS_URL=redis://localhost:6379/0

      # Kafka Configuration (optional)
      KAFKA_ENABLED=false

      # Email/SMTP Configuration (update with your values)
      # MAIL_USERNAME=your-email@domain.com
      # MAIL_PASSWORD=your-email-password
      # SMTP_HOST=smtp.gmail.com
      # SMTP_PORT=587
      # SMTP_DOMAIN=yourdomain.com

      # AWS Configuration (for S3, etc.)
      # AWS_ACCESS_KEY_ID=your-aws-access-key
      # AWS_SECRET_ACCESS_KEY=your-aws-secret-key
      # AWS_REGION=us-east-1
      # S3_BUCKET=your-s3-bucket

      # Sidekiq Web UI Authentication (uncomment and set strong passwords)
      # SIDEKIQ_USERNAME=admin
      # SIDEKIQ_PASSWORD=#{SecureRandom.hex(16)}

      # Basic Auth for staging/admin areas (uncomment if needed)
      # BASIC_AUTH_USERNAME=admin
      # BASIC_AUTH_PASSWORD=#{SecureRandom.hex(16)}

      # Error Tracking (uncomment if using Sentry)
      # SENTRY_DSN=your-sentry-dsn

      # Performance Monitoring (uncomment if using New Relic)
      # NEW_RELIC_LICENSE_KEY=your-newrelic-license-key

      # SSL Configuration (uncomment if needed)
      # SSL_CERT_PATH=/path/to/ssl/cert.pem
      # SSL_KEY_PATH=/path/to/ssl/key.pem
    ENV

    File.write(Rails.root.join(".env.production"), env_content)
    puts "✅ .env.production file created"

    puts "\n🎯 Production setup completed!"
    puts "\n📋 Next steps:"
    puts "1. Source the environment: source .env.production"
    puts "2. Test with: RAILS_ENV=production rake debug:credentials"
    puts "3. Restart your Rails server"

    puts "\n⚠️  Security reminders:"
    puts "- Add .env.production to .gitignore"
    puts "- Keep master key secure"
    puts "- Test database connection"
  end

  desc "Test production database connection"
  task test_db: :environment do
    puts "🗄️  Testing production database connection..."

    begin
      # Test basic connection
      ActiveRecord::Base.connection.execute("SELECT 1")
      puts "✅ Database connection successful"

      # Test database info
      db_name = ActiveRecord::Base.connection.current_database
      puts "📊 Connected to: #{db_name}"

      # Test a simple query
      user_count = User.count rescue 0
      company_count = Company.count rescue 0
      domain_count = Domain.count rescue 0

      puts "📈 Record counts:"
      puts "  Users: #{user_count}"
      puts "  Companies: #{company_count}"
      puts "  Domains: #{domain_count}"

    rescue => e
      puts "❌ Database connection failed: #{e.message}"
      puts "\n🔧 Troubleshooting:"
      puts "1. Check DATABASE_URL environment variable"
      puts "2. Verify database server is running"
      puts "3. Check network connectivity"
      puts "4. Verify credentials"
    end
  end
end
