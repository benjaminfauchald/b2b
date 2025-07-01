# Enhanced Guard test logger for continuous monitoring
require "json"
require "fileutils"

class GuardTestLogger
  LOG_DIR = "tmp/guard_logs"
  CURRENT_FAILURES_FILE = File.join(LOG_DIR, "current_failures.json")
  FAILURE_HISTORY_FILE = File.join(LOG_DIR, "failure_history.log")
  FAILURE_SUMMARY_FILE = File.join(LOG_DIR, "failure_summary.md")

  def self.ensure_log_directory
    FileUtils.mkdir_p(LOG_DIR)
  end

  def self.log_test_run(result, failed_specs = [])
    ensure_log_directory

    timestamp = Time.current

    # Log the summary
    summary = {
      timestamp: timestamp.iso8601,
      total_examples: result.example_count,
      failures: result.failure_count,
      pending: result.pending_count,
      duration: result.duration,
      status: result.failure_count > 0 ? "failed" : "passed"
    }

    # Update current failures file
    if result.failure_count > 0
      current_failures = {
        last_updated: timestamp.iso8601,
        failure_count: failed_specs.length,
        failures: failed_specs.map do |spec|
          {
            description: spec[:description],
            file_path: spec[:file_path],
            line_number: spec[:line_number],
            exception: spec[:exception],
            full_description: spec[:full_description] || spec[:description]
          }
        end
      }

      File.write(CURRENT_FAILURES_FILE, JSON.pretty_generate(current_failures))

      # Append to history log
      File.open(FAILURE_HISTORY_FILE, "a") do |f|
        f.puts "=== #{timestamp} ==="
        f.puts "Failures: #{result.failure_count}"
        failed_specs.each do |spec|
          f.puts "  - #{spec[:file_path]}:#{spec[:line_number]} - #{spec[:description]}"
        end
        f.puts ""
      end

      # Generate markdown summary
      generate_markdown_summary(current_failures)
    else
      # Clear current failures if all tests pass
      if File.exist?(CURRENT_FAILURES_FILE)
        File.write(CURRENT_FAILURES_FILE, JSON.pretty_generate({
          last_updated: timestamp.iso8601,
          failure_count: 0,
          failures: [],
          message: "All tests passing! 🎉"
        }))
      end

      File.write(FAILURE_SUMMARY_FILE, "# All Tests Passing! 🎉\n\nLast successful run: #{timestamp}")
    end

    # Log summary to console
    if result.failure_count > 0
      puts "\n📊 Test Run Summary:"
      puts "  ❌ #{result.failure_count} failures"
      puts "  ✅ #{result.example_count - result.failure_count} passed"
      puts "  ⏰ Duration: #{result.duration.round(2)}s"
      puts "  📁 Logs: #{LOG_DIR}/"
    end
  end

  def self.generate_markdown_summary(current_failures)
    md = "# Current Test Failures\n\n"
    md += "**Last Updated:** #{current_failures[:last_updated]}\n"
    md += "**Total Failures:** #{current_failures[:failure_count]}\n\n"

    if current_failures[:failures].any?
      md += "## Failed Tests\n\n"

      current_failures[:failures].each_with_index do |failure, index|
        md += "### #{index + 1}. #{failure[:full_description]}\n\n"
        md += "**File:** `#{failure[:file_path]}:#{failure[:line_number]}`\n\n"
        md += "**Error:**\n```\n#{failure[:exception]}\n```\n\n"
        md += "**Run this test:**\n```bash\nbundle exec rspec #{failure[:file_path]}:#{failure[:line_number]}\n```\n\n"
        md += "---\n\n"
      end

      md += "## Quick Fix Commands\n\n"
      md += "Run all failing tests:\n```bash\n"
      current_failures[:failures].each do |failure|
        md += "bundle exec rspec #{failure[:file_path]}:#{failure[:line_number]}\n"
      end
      md += "```\n"
    end

    File.write(FAILURE_SUMMARY_FILE, md)
  end

  def self.check_for_new_failures
    return unless File.exist?(CURRENT_FAILURES_FILE)

    current = JSON.parse(File.read(CURRENT_FAILURES_FILE))
    return if current["failure_count"] == 0

    puts "\n⚠️  Current test failures detected!"
    puts "View details: cat #{FAILURE_SUMMARY_FILE}"
    puts "Or JSON: cat #{CURRENT_FAILURES_FILE}"
  end
end
