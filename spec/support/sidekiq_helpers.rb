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

  config.before(:each) do
    # Clear all jobs before each test
    Sidekiq::Worker.clear_all
  end

  # Extra cleanup for worker specs
  config.before(:each, type: :worker) do
    # Ensure clean state for worker tests
    Sidekiq::Worker.clear_all
    clear_sidekiq_queues
  end

  # Extra cleanup for system specs that test queuing
  config.before(:each, type: :system) do |example|
    if example.metadata[:full_description].include?("queue") ||
       example.metadata[:full_description].include?("Queue")
      Sidekiq::Worker.clear_all
      clear_sidekiq_queues
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
