# Guard helper for Claude integration
class GuardClaudeHelper
  def self.on_test_failure(failed_specs)
    # Create a failure report file that you can easily share with Claude
    failure_report = generate_failure_report(failed_specs)
    
    # Write to a file you can quickly copy/paste to Claude
    File.write("tmp/test_failures.md", failure_report)
    
    # Show notification with instructions
    notify_user_about_failures(failed_specs.length)
    
    # Optional: Open the failure report in your editor
    system("open tmp/test_failures.md") if RUBY_PLATFORM.include?('darwin')
  end
  
  private
  
  def self.generate_failure_report(failed_specs)
    report = "# Test Failure Report\n\n"
    report += "Generated at: #{Time.current}\n\n"
    report += "## Failed Tests (#{failed_specs.length})\n\n"
    
    failed_specs.each_with_index do |spec, index|
      report += "### #{index + 1}. #{spec[:description]}\n\n"
      report += "**File:** `#{spec[:file_path]}`\n\n"
      report += "**Error:**\n```\n#{spec[:exception]}\n```\n\n"
      report += "**Run specific test:**\n```bash\nbundle exec rspec #{spec[:file_path]}:#{spec[:line_number]}\n```\n\n"
      report += "---\n\n"
    end
    
    report += "## Quick Claude Prompt\n\n"
    report += "```\nPlease fix these failing tests. The failures are:\n\n"
    failed_specs.each do |spec|
      report += "- #{spec[:description]} in #{spec[:file_path]}\n"
    end
    report += "```\n"
    
    report
  end
  
  def self.notify_user_about_failures(count)
    message = "#{count} test(s) failing! Failure report generated in tmp/test_failures.md"
    
    if RUBY_PLATFORM.include?('darwin')
      system("osascript -e 'display notification \"#{message}\" with title \"Guard: Tests Failed\" sound name \"Basso\"'")
    end
    
    puts "\n" + "🚨" * 50
    puts "❌ TESTS FAILING - Claude Helper Ready!"
    puts "📝 Failure report: tmp/test_failures.md"
    puts "📋 Copy the report to Claude for automated fixing"
    puts "🚨" * 50 + "\n"
  end
end