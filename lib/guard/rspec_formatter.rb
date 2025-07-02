# Custom RSpec formatter for Guard that logs failures
require "json"
require_relative "../guard_test_logger"

# Only load in non-CI environments or when Guard is present
# Skip in CI eager loading to prevent constant resolution issues
return if ENV["CI"] && !defined?(Guard)

# Load RSpec core first to ensure RSpec is available
require "rspec/core" if defined?(RSpec)

module Guard
  class RspecFormatter
    # Only register if RSpec is available
    if defined?(RSpec::Core::Formatters)
      RSpec::Core::Formatters.register self, :dump_summary, :example_failed
    end

    def initialize(output)
      @output = output
      @failed_examples = []
    end

    def example_failed(notification)
      example = notification.example
      @failed_examples << {
        description: example.description,
        file_path: example.metadata[:file_path],
        line_number: example.metadata[:line_number],
        exception: example.exception.message,
        full_description: example.full_description
      }
    end

    def dump_summary(summary)
      result = OpenStruct.new(
        example_count: summary.example_count,
        failure_count: summary.failure_count,
        pending_count: summary.pending_count,
        duration: summary.duration
      )

      # Log test results
      GuardTestLogger.log_test_run(result, @failed_examples)
    end
  end
end
