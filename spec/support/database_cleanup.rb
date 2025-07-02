# Comprehensive database cleanup strategy for tests
# Fixes state pollution between different test types

RSpec.configure do |config|
  # Use database truncation for system tests to ensure complete cleanup
  config.before(:suite) do
    # Ensure we have database_cleaner available
    require 'database_cleaner-active_record'
    DatabaseCleaner[:active_record].strategy = :truncation
  end

  # Comprehensive cleanup for system tests (they don't use transactions)
  config.before(:each, type: :system) do
    # Use safer cleanup for system tests to avoid deadlocks
    begin
      # Try less aggressive cleanup first
      Company.destroy_all
      ServiceAuditLog.destroy_all
      Domain.destroy_all
      Person.destroy_all
      User.destroy_all
      ServiceConfiguration.destroy_all
    rescue => e
      # If regular cleanup fails, try database truncation
      begin
        DatabaseCleaner[:active_record].clean
      rescue => truncation_error
        # Log and continue - don't fail tests due to cleanup issues
        puts "Database cleanup failed: #{truncation_error.message}"
      end
    end
    
    # Clear all Sidekiq state
    Sidekiq::Worker.clear_all if defined?(Sidekiq::Worker)
    Sidekiq::Testing.fake! # Reset to consistent mode
    
    # Clear Redis cache and queues
    if defined?(Redis.current)
      Redis.current.flushdb rescue nil
    end
    
    # Clear Rails cache
    Rails.cache.clear rescue nil
    
    # Reset authentication state
    if defined?(Warden) && Warden.respond_to?(:test_reset!)
      Warden.test_reset!
    end
    
    # Clear ActionCable connections
    ActionCable.server.restart if defined?(ActionCable) rescue nil
  end

  # Cleanup after system tests to prevent state bleeding
  config.after(:each, type: :system) do
    # Additional cleanup after system tests
    if defined?(Warden) && Warden.respond_to?(:test_reset!)
      Warden.test_reset!
    end
    Sidekiq::Worker.clear_all if defined?(Sidekiq::Worker)
  end

  # Enhanced cleanup for component tests that use database data
  config.before(:each, type: :component) do |example|
    if example.metadata[:full_description].include?("Service Stats") ||
       example.metadata[:full_description].include?("Business Logic")
      # Use truncation for component tests that need clean state
      DatabaseCleaner[:active_record].clean
      Sidekiq::Worker.clear_all if defined?(Sidekiq::Worker)
    end
  end

  # Enhanced cleanup for specific test types that need complete state reset
  config.before(:each) do |example|
    if example.metadata[:full_description].include?("Service Stats") ||
       example.metadata[:full_description].include?("Business Logic") ||
       example.metadata[:file_path].include?("service_stats_consistency_spec.rb") ||
       example.metadata[:file_path].include?("queue") ||
       example.metadata[:file_path].include?("worker")
      
      # Ensure clean state for sensitive tests
      Sidekiq::Worker.clear_all if defined?(Sidekiq::Worker)
      Sidekiq::Testing.fake! # Consistent mode
      
      # Clear any cached service data
      Rails.cache.clear rescue nil
    end
  end

  # Cleanup after worker tests to prevent Sidekiq state pollution
  config.after(:each, type: :worker) do
    Sidekiq::Worker.clear_all if defined?(Sidekiq::Worker)
    Sidekiq::Testing.fake! # Reset to consistent mode
  end
end
