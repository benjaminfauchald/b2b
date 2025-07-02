# Sidekiq test helpers
require 'sidekiq/api'

module SidekiqHelpers
  def clear_sidekiq_queues
    Sidekiq::Queue.all.each(&:clear)
    Sidekiq::RetrySet.new.clear
    Sidekiq::ScheduledSet.new.clear
    Sidekiq::DeadSet.new.clear
  end

  def perform_enqueued_jobs
    Sidekiq::Worker.drain_all
  end

  def sidekiq_queue_size(queue_name)
    Sidekiq::Queue.new(queue_name).size
  end
end

RSpec.configure do |config|
  config.include SidekiqHelpers

  # Global Sidekiq state management for all tests
  config.before(:each) do
    # Clear all jobs and reset to consistent state
    Sidekiq::Worker.clear_all
    Sidekiq::Testing.fake! # Consistent mode across all test types

    # Clear all queue-specific state
    clear_sidekiq_queues
  end

  # Enhanced cleanup for worker specs - most critical for our failing tests
  config.before(:each, type: :worker) do
    # Ensure completely clean state for worker tests
    Sidekiq::Worker.clear_all
    Sidekiq::Testing.fake!
    clear_sidekiq_queues

    # Clear any Redis-based queue state
    Sidekiq::Queue.new.clear rescue nil
    Sidekiq::RetrySet.new.clear rescue nil
    Sidekiq::DeadSet.new.clear rescue nil
  end

  # Enhanced cleanup for system specs that test queuing
  config.before(:each, type: :system) do |example|
    if example.metadata[:full_description].include?("queue") ||
       example.metadata[:full_description].include?("Queue") ||
       example.metadata[:file_path].include?("queue")

      # Complete Sidekiq state reset for queue-related system tests
      Sidekiq::Worker.clear_all
      Sidekiq::Testing.fake!
      clear_sidekiq_queues

      # Clear actual Redis queues that system tests might interact with
      begin
        Sidekiq.redis { |conn| conn.flushdb }
      rescue => e
        # Ignore Redis connection errors in test environment
      end
    end
  end

  # After hooks to ensure cleanup
  config.after(:each, type: :worker) do
    Sidekiq::Worker.clear_all
    Sidekiq::Testing.fake!
  end

  config.after(:each, type: :system) do |example|
    if example.metadata[:full_description].include?("queue") ||
       example.metadata[:full_description].include?("Queue") ||
       example.metadata[:file_path].include?("queue")
      Sidekiq::Worker.clear_all
      Sidekiq::Testing.fake!
    end
  end

  config.around(:each, sidekiq: :inline) do |example|
    Sidekiq::Testing.inline! do
      example.run
    end
  end

  config.around(:each, sidekiq: :fake) do |example|
    Sidekiq::Testing.fake! do
      example.run
    end
  end

  config.around(:each, sidekiq: :disable) do |example|
    Sidekiq::Testing.disable! do
      example.run
    end
  end
end
