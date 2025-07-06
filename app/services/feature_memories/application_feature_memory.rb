# frozen_string_literal: true

require 'fileutils'
require 'digest'

module FeatureMemories
  # Base class for all feature memory implementations
  # Provides DSL for documenting feature development in a structured way
  class ApplicationFeatureMemory
  include ActiveSupport::Configurable

  class_attribute :feature_id
  
  class << self
    def feature_data
      @feature_data ||= load_persisted_data
    end

    def save_data!
      persist_data(feature_data)
    end

    private

    def persistence_file_path
      Rails.root.join("tmp", "idm_data", "#{feature_id}.json")
    end

    def load_persisted_data
      return {} unless File.exist?(persistence_file_path)
      
      begin
        data = JSON.parse(File.read(persistence_file_path), symbolize_names: true)
        # Convert timestamps back to Time objects if needed
        convert_timestamps_from_persistence(data)
      rescue JSON::ParserError, StandardError => e
        Rails.logger.warn "Failed to load IDM data for #{feature_id}: #{e.message}"
        {}
      end
    end

    def persist_data(data)
      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(persistence_file_path))
      
      # Convert any Time objects to strings for JSON serialization
      serializable_data = convert_timestamps_for_persistence(data.deep_dup)
      
      File.write(persistence_file_path, JSON.pretty_generate(serializable_data))
    rescue StandardError => e
      Rails.logger.error "Failed to persist IDM data for #{feature_id}: #{e.message}"
    end

    def convert_timestamps_for_persistence(data)
      case data
      when Hash
        data.transform_values { |v| convert_timestamps_for_persistence(v) }
      when Array
        data.map { |v| convert_timestamps_for_persistence(v) }
      when Time
        data.to_s
      else
        data
      end
    end

    def convert_timestamps_from_persistence(data)
      case data
      when Hash
        data.transform_values { |v| convert_timestamps_from_persistence(v) }
      when Array
        data.map { |v| convert_timestamps_from_persistence(v) }
      when String
        # Try to parse as timestamp if it looks like one
        if data.match?(/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/)
          begin
            Time.parse(data)
          rescue ArgumentError
            data
          end
        else
          data
        end
      else
        data
      end
    end

    public
    def feature_spec(&block)
      feature_data[:spec] ||= {}
      FeatureSpecDSL.new(feature_data[:spec]).instance_eval(&block)
      save_data!
    end

    def implementation_plan(&block)
      feature_data[:implementation_plan] ||= []
      ImplementationPlanDSL.new(feature_data[:implementation_plan]).instance_eval(&block)
      save_data!
    end

    def implementation_log(&block)
      feature_data[:implementation_log] ||= []
      ImplementationLogDSL.new(feature_data[:implementation_log]).instance_eval(&block)
      save_data!
    end

    def troubleshooting(&block)
      feature_data[:troubleshooting] ||= []
      TroubleshootingDSL.new(feature_data[:troubleshooting]).instance_eval(&block)
      save_data!
    end

    def performance_metrics(&block)
      feature_data[:performance_metrics] ||= {}
      PerformanceMetricsDSL.new(feature_data[:performance_metrics]).instance_eval(&block)
      save_data!
    end

    def find(feature_name)
      class_name = "FeatureMemories::#{feature_name.to_s.camelize}"
      class_name.constantize
    rescue NameError
      nil
    end

    def all
      Dir[Rails.root.join("app/services/feature_memories/*.rb")].map do |file|
        next if file.include?("application_feature_memory")
        next if file.include?("feature_memory_markdown_exporter")
        
        class_name = File.basename(file, ".rb").camelize
        "FeatureMemories::#{class_name}".constantize rescue nil
      end.compact
    end

    def status
      implementation_log = feature_data[:implementation_log] || []
      return :not_started if implementation_log.empty?
      
      # If all tasks are completed, feature is completed regardless of log status
      plan_status_data = plan_status
      if plan_status_data[:total] > 0 && plan_status_data[:completion_percentage] == 100.0
        return :completed
      end
      
      # Find the most recent meaningful status (not planning)
      meaningful_step = implementation_log.reverse.find { |step| 
        step[:status] && step[:status].to_s != 'planning' 
      }
      
      return meaningful_step[:status].to_sym if meaningful_step
      
      # Fall back to last step or planning
      last_step = implementation_log.last
      last_step ? (last_step[:status] || :planning) : :not_started
    end

    def current_step
      implementation_log = feature_data[:implementation_log] || []
      implementation_log.find { |step| step[:status] == :in_progress } || implementation_log.last
    end

    def to_markdown
      FeatureMemoryMarkdownExporter.new(self).export
    end

    def log_step(action, **options)
      implementation_log do
        step Time.current.to_s do
          self.action action
          options.each do |key, value|
            send(key, value) if respond_to?(key)
          end
        end
      end
    end

    # Plan management methods
    def add_task(description, **options)
      implementation_plan do
        task description do
          options.each do |key, value|
            send(key, value) if respond_to?(key)
          end
        end
      end
    end

    def update_task(task_id, **updates)
      plan_data = feature_data[:implementation_plan] || []
      plan_dsl = ImplementationPlanDSL.new(plan_data)
      plan_dsl.update_task(task_id, **updates)
      save_data!
    end

    def plan_status
      plan_data = feature_data[:implementation_plan] || []
      plan_dsl = ImplementationPlanDSL.new(plan_data)
      
      {
        total: plan_data.size,
        pending: plan_dsl.pending_tasks.size,
        in_progress: plan_dsl.in_progress_tasks.size,
        completed: plan_dsl.completed_tasks.size,
        completion_percentage: plan_data.empty? ? 0 : (plan_dsl.completed_tasks.size.to_f / plan_data.size * 100).round(1)
      }
    end

    def current_tasks
      plan_data = feature_data[:implementation_plan] || []
      plan_dsl = ImplementationPlanDSL.new(plan_data)
      plan_dsl.in_progress_tasks
    end

    def next_task
      plan_data = feature_data[:implementation_plan] || []
      plan_dsl = ImplementationPlanDSL.new(plan_data)
      plan_dsl.pending_tasks.first
    end
  end

  # DSL Classes
  class FeatureSpecDSL
    def initialize(data)
      @data = data
    end

    def description(text)
      @data[:description] = text
    end

    def requested_by(user)
      @data[:requested_by] = user
    end

    def created_at(date)
      @data[:created_at] = date
    end

    def requirements(&block)
      @data[:requirements] ||= {}
      RequirementsDSL.new(@data[:requirements]).instance_eval(&block)
    end

    def test_data(&block)
      @data[:test_data] ||= {}
      TestDataDSL.new(@data[:test_data]).instance_eval(&block)
    end
  end

  class RequirementsDSL
    def initialize(data)
      @data = data
    end

    def feature_type(type)
      @data[:feature_type] = type
    end

    def user_interaction(interaction)
      @data[:user_interaction] = interaction
    end

    def components(components_list)
      @data[:components] = components_list
    end

    def javascript_framework(framework)
      @data[:javascript_framework] = framework
    end

    def api_endpoint(endpoint)
      @data[:api_endpoint] = endpoint
    end

    def debounce_delay(delay)
      @data[:debounce_delay] = delay
    end

    def min_characters(min)
      @data[:min_characters] = min
    end

    def max_suggestions(max)
      @data[:max_suggestions] = max
    end

    def input_fields(**fields)
      @data[:input_fields] = fields
    end

    def output(model_or_data)
      @data[:output] = model_or_data
    end

    def queue_system(system)
      @data[:queue_system] = system
    end

    def ui_location(location)
      @data[:ui_location] = location
    end

    def dependencies(deps)
      @data[:dependencies] = deps
    end

    def method_missing(method_name, *args, &block)
      if args.length == 1 && !block_given?
        @data[method_name] = args.first
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  class TestDataDSL
    def initialize(data)
      @data = data
    end

    def method_missing(method_name, *args)
      @data[method_name] = args.first
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  class ImplementationPlanDSL
    def initialize(data)
      @data = data
    end

    def task(description, &block)
      # Check if task already exists by description to avoid duplicates
      existing_task = @data.find { |t| t[:description] == description }
      
      if existing_task
        # Update existing task if block is given
        TaskDSL.new(existing_task).instance_eval(&block) if block_given?
        return existing_task[:id]
      end
      
      # Create new task with deterministic ID based on description
      task_id = Digest::SHA256.hexdigest(description)[0..15] # First 16 chars for shorter ID
      
      task_data = { 
        id: task_id,
        description: description,
        status: :pending,
        created_at: Time.current.to_s
      }
      TaskDSL.new(task_data).instance_eval(&block) if block_given?
      @data << task_data
      task_data[:id]
    end

    def update_task(task_id, status: nil, notes: nil)
      task = @data.find { |t| t[:id] == task_id }
      return unless task

      task[:status] = status if status
      task[:notes] = notes if notes
      task[:updated_at] = Time.current.to_s
      task
    end

    def find_task(task_id)
      @data.find { |t| t[:id] == task_id }
    end

    def pending_tasks
      @data.select { |t| t[:status].to_s == 'pending' }
    end

    def in_progress_tasks
      @data.select { |t| t[:status].to_s == 'in_progress' }
    end

    def completed_tasks
      @data.select { |t| t[:status].to_s == 'completed' }
    end
  end

  class TaskDSL
    def initialize(data)
      @data = data
    end

    def priority(level)
      @data[:priority] = level
    end

    def assignee(name)
      @data[:assignee] = name
    end

    def due_date(date)
      @data[:due_date] = date
    end

    def dependencies(task_ids)
      @data[:dependencies] = task_ids
    end

    def estimated_time(time)
      @data[:estimated_time] = time
    end

    def tags(*tags)
      @data[:tags] = tags
    end

    def status(status)
      @data[:status] = status
    end

    def notes(text)
      @data[:notes] = text
    end
  end

  class ImplementationLogDSL
    def initialize(data)
      @data = data
    end

    def step(timestamp, &block)
      step_data = { timestamp: timestamp }
      StepDSL.new(step_data).instance_eval(&block)
      @data << step_data
    end
  end

  class StepDSL
    def initialize(data)
      @data = data
    end

    def action(text)
      @data[:action] = text
    end

    def decision(text)
      @data[:decision] = text
    end

    def challenge(text)
      @data[:challenge] = text
    end

    def solution(text)
      @data[:solution] = text
    end

    def code_ref(ref)
      @data[:code_ref] = ref
    end

    def test_ref(ref)
      @data[:test_ref] = ref
    end

    def status(status)
      @data[:status] = status
    end

    def notes(text)
      @data[:notes] = text
    end
  end

  class TroubleshootingDSL
    def initialize(data)
      @data = data
    end

    def issue(description, &block)
      issue_data = { description: description }
      IssueDSL.new(issue_data).instance_eval(&block)
      @data << issue_data
    end
  end

  class IssueDSL
    def initialize(data)
      @data = data
    end

    def cause(text)
      @data[:cause] = text
    end

    def solution(text)
      @data[:solution] = text
    end

    def code_example(text)
      @data[:code_example] = text
    end

    def prevention(text)
      @data[:prevention] = text
    end
  end

  class PerformanceMetricsDSL
    def initialize(data)
      @data = data
    end

    def method_missing(method_name, *args)
      @data[method_name] = args.first
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end
end

# Helper module for code integration
module FeatureMemoryIntegration
  extend ActiveSupport::Concern

  class_methods do
    def feature_memory(feature_name, &block)
      memory_class = ApplicationFeatureMemory.find(feature_name)
      return unless memory_class

      if block_given?
        FeatureMemoryContext.new(memory_class).instance_eval(&block)
      end

      memory_class
    end
  end

  class FeatureMemoryContext
    def initialize(memory_class)
      @memory_class = memory_class
    end

    def log_decision(text)
      @memory_class.log_step("Decision logged", decision: text, status: :in_progress)
    end

    def log_challenge(text, solution: nil)
      @memory_class.log_step("Challenge encountered", 
                           challenge: text, 
                           solution: solution,
                           status: :in_progress)
    end

    def log_completion(text)
      @memory_class.log_step(text, status: :completed)
    end
  end
end
end

# Include FeatureMemoryIntegration in base classes
# This needs to be done in each base class file to avoid load order issues