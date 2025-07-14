# frozen_string_literal: true

module FeatureMemories
  # UI Testing DSL Extensions for Feature Memory System
  # Provides comprehensive UI testing tracking and validation for IDM features
  class UITestingDSL
    def initialize(data)
      @data = data
    end

    def happy_path(description, &block)
      test_scenario(description, :happy_path, &block)
    end

    def edge_case(description, &block)
      test_scenario(description, :edge_case, &block)
    end

    def error_state(description, &block)
      test_scenario(description, :error_state, &block)
    end

    def accessibility(description, &block)
      test_scenario(description, :accessibility, &block)
    end

    def performance(description, &block)
      test_scenario(description, :performance, &block)
    end

    def integration(description, &block)
      test_scenario(description, :integration, &block)
    end

    def test_coverage_requirement(percentage)
      @data[:coverage_requirement] = percentage
    end

    def mandatory_before_completion(required = true)
      @data[:mandatory_completion] = required
    end

    def test_frameworks(*frameworks)
      @data[:frameworks] = frameworks.flatten
    end

    def test_environment(env)
      @data[:test_environment] = env
    end

    def scenario(description, &block)
      test_scenario(description, :general, &block)
    end

    private

    def test_scenario(description, scenario_type, &block)
      @data[:test_scenarios] ||= []
      
      scenario_data = {
        id: generate_scenario_id(description),
        description: description,
        scenario_type: scenario_type,
        status: :pending,
        created_at: Time.current.to_s
      }
      
      UITestScenarioDSL.new(scenario_data).instance_eval(&block) if block_given?
      @data[:test_scenarios] << scenario_data
      scenario_data[:id]
    end

    def generate_scenario_id(description)
      # Create deterministic ID based on description
      Digest::SHA256.hexdigest(description.downcase.strip)[0..15]
    end
  end

  # DSL for individual test scenarios
  class UITestScenarioDSL
    def initialize(data)
      @data = data
    end

    def test_type(type)
      @data[:test_type] = type # :unit, :integration, :system, :e2e
    end

    def test_file(file_path)
      @data[:test_file] = file_path
    end

    def user_actions(actions)
      @data[:user_actions] = actions.is_a?(Array) ? actions : [actions]
    end

    def expected_outcome(outcome)
      @data[:expected_outcome] = outcome
    end

    def prerequisites(prereqs)
      @data[:prerequisites] = prereqs.is_a?(Array) ? prereqs : [prereqs]
    end

    def test_data(data)
      @data[:test_data] = data
    end

    def browser_requirements(requirements)
      @data[:browser_requirements] = requirements
    end

    def viewport_size(width, height)
      @data[:viewport_size] = { width: width, height: height }
    end

    def accessibility_requirements(requirements)
      @data[:accessibility_requirements] = requirements.is_a?(Array) ? requirements : [requirements]
    end

    def performance_thresholds(thresholds)
      @data[:performance_thresholds] = thresholds
    end

    def priority(level)
      @data[:priority] = level # :critical, :high, :medium, :low
    end

    def tags(*tags)
      @data[:tags] = tags.flatten
    end

    def status(status)
      @data[:status] = status # :pending, :in_progress, :passed, :failed, :skipped
    end

    def notes(text)
      @data[:notes] = text
    end

    def estimated_time(time)
      @data[:estimated_time] = time
    end

    def description(text)
      @data[:description] = text
    end

    def test_steps(steps)
      @data[:test_steps] = steps.is_a?(Array) ? steps : [steps]
    end

    def expected_result(result)
      @data[:expected_result] = result
    end

    def automation_level(level)
      @data[:automation_level] = level # :fully_automated, :semi_automated, :manual
    end

    def components_under_test(components)
      @data[:components_under_test] = components.is_a?(Array) ? components : [components]
    end

    def api_endpoints(endpoints)
      @data[:api_endpoints] = endpoints.is_a?(Array) ? endpoints : [endpoints]
    end

    def database_requirements(requirements)
      @data[:database_requirements] = requirements
    end

    def external_dependencies(dependencies)
      @data[:external_dependencies] = dependencies.is_a?(Array) ? dependencies : [dependencies]
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

  # Test execution tracking DSL
  class UITestExecutionDSL
    def initialize(data)
      @data = data
    end

    def execution(timestamp, &block)
      execution_data = { 
        timestamp: timestamp,
        duration: nil,
        result: nil,
        failures: [],
        screenshots: [],
        logs: []
      }
      UITestExecutionStepDSL.new(execution_data).instance_eval(&block) if block_given?
      @data[:executions] ||= []
      @data[:executions] << execution_data
    end
  end

  # Test execution step DSL
  class UITestExecutionStepDSL
    def initialize(data)
      @data = data
    end

    def duration(seconds)
      @data[:duration] = seconds
    end

    def result(status)
      @data[:result] = status # :passed, :failed, :error, :skipped
    end

    def failure(message, details = nil)
      @data[:failures] << { message: message, details: details }
    end

    def screenshot(path, description = nil)
      @data[:screenshots] << { path: path, description: description, timestamp: Time.current.to_s }
    end

    def log_entry(level, message)
      @data[:logs] << { level: level, message: message, timestamp: Time.current.to_s }
    end

    def browser_info(info)
      @data[:browser_info] = info
    end

    def viewport_info(info)
      @data[:viewport_info] = info
    end

    def performance_metrics(metrics)
      @data[:performance_metrics] = metrics
    end

    def accessibility_violations(violations)
      @data[:accessibility_violations] = violations
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

  # Helper methods for UI testing status and validation
  module UITestingHelpers
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      def ui_test_status
        ui_data = feature_data[:ui_testing] || {}
        scenarios = ui_data[:test_scenarios] || []
        
        return { status: :no_tests, message: "No UI tests defined" } if scenarios.empty?
      
        total = scenarios.count
        passed = scenarios.count { |s| s[:status] == :passed }
        failed = scenarios.count { |s| s[:status] == :failed }
        pending = scenarios.count { |s| s[:status] == :pending }
        in_progress = scenarios.count { |s| s[:status] == :in_progress }
        
        coverage_req = ui_data[:coverage_requirement] || 90
        pass_percentage = total > 0 ? (passed.to_f / total * 100).round(1) : 0
        
        status = if failed > 0
          :failed
        elsif pending > 0 || in_progress > 0
          :incomplete
        elsif pass_percentage >= coverage_req
          :passed
        else
          :insufficient_coverage
        end
        
        {
          status: status,
          total: total,
          passed: passed,
          failed: failed,
          pending: pending,
          in_progress: in_progress,
          pass_percentage: pass_percentage,
          coverage_requirement: coverage_req,
          mandatory_completion: ui_data[:mandatory_completion] != false
        }
      end

      def ui_test_scenarios_by_type
        ui_data = feature_data[:ui_testing] || {}
        scenarios = ui_data[:test_scenarios] || []
        
        scenarios.group_by { |s| s[:scenario_type] }
      end

      def critical_ui_tests
        ui_data = feature_data[:ui_testing] || {}
        scenarios = ui_data[:test_scenarios] || []
        
        scenarios.select { |s| s[:priority] == :critical }
      end

      def failed_ui_tests
        ui_data = feature_data[:ui_testing] || {}
        scenarios = ui_data[:test_scenarios] || []
        
        scenarios.select { |s| s[:status] == :failed }
      end

      def update_ui_test_status(scenario_id, status, **details)
        ui_data = feature_data[:ui_testing] ||= {}
        scenarios = ui_data[:test_scenarios] ||= []
        
        scenario = scenarios.find { |s| s[:id] == scenario_id }
        return false unless scenario
        
        scenario[:status] = status
        scenario[:updated_at] = Time.current.to_s
        details.each { |key, value| scenario[key] = value }
        
        save_data!
        true
      end

      def log_ui_test_execution(scenario_id, &block)
        ui_data = feature_data[:ui_testing] ||= {}
        scenarios = ui_data[:test_scenarios] ||= []
        
        scenario = scenarios.find { |s| s[:id] == scenario_id }
        return false unless scenario
        
        scenario[:executions] ||= []
        execution_dsl = UITestExecutionDSL.new(scenario)
        execution_dsl.execution(Time.current.to_s, &block) if block_given?
        
        save_data!
        true
      end

      def ready_for_completion?
        ui_status = ui_test_status
        
        # If UI testing is not mandatory, allow completion
        return true unless ui_status[:mandatory_completion]
        
        # Check if all critical tests pass
        critical_tests = critical_ui_tests
        critical_passed = critical_tests.all? { |t| t[:status] == :passed }
        
        # Check overall coverage
        coverage_met = ui_status[:pass_percentage] >= ui_status[:coverage_requirement]
        
        critical_passed && coverage_met && ui_status[:failed] == 0
      end

      def ui_testing_blockers
        blockers = []
        ui_status = ui_test_status
        
        return blockers unless ui_status[:mandatory_completion]
        
        if ui_status[:failed] > 0
          blockers << "#{ui_status[:failed]} UI test(s) failing"
        end
        
        if ui_status[:pass_percentage] < ui_status[:coverage_requirement]
          blockers << "UI test coverage #{ui_status[:pass_percentage]}% below requirement #{ui_status[:coverage_requirement]}%"
        end
        
        critical_failures = critical_ui_tests.select { |t| t[:status] == :failed }
        if critical_failures.any?
          blockers << "#{critical_failures.count} critical UI test(s) failing"
        end
        
        blockers
      end
    end
  end
end