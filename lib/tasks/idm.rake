# frozen_string_literal: true

# Ensure feature memory classes are loaded
require_relative "../../app/services/feature_memories/application_feature_memory"
require_relative "../../app/services/feature_memories/feature_memory_markdown_exporter"

namespace :feature_memory do
  desc "Show status of a feature memory"
  task :status, [:feature_name] => :environment do |_task, args|
    if args[:feature_name].blank?
      show_all_status
    else
      show_feature_status(args[:feature_name])
    end
  end

  desc "Export feature memory to markdown"
  task :export, [:feature_name] => :environment do |_task, args|
    unless args[:feature_name]
      puts "Usage: rails feature_memory:export[feature_name]"
      exit 1
    end

    memory = FeatureMemories::ApplicationFeatureMemory.find(args[:feature_name])
    unless memory
      puts "Feature memory '#{args[:feature_name]}' not found"
      exit 1
    end

    markdown = memory.to_markdown
    filename = "tmp/feature_memory_#{args[:feature_name]}_#{Time.current.to_i}.md"
    
    File.write(filename, markdown)
    puts "Exported to: #{filename}"
  end

  desc "Resume work on a feature"
  task :resume, [:feature_name] => :environment do |_task, args|
    unless args[:feature_name]
      puts "Usage: rails feature_memory:resume[feature_name]"
      exit 1
    end

    memory = FeatureMemories::ApplicationFeatureMemory.find(args[:feature_name])
    unless memory
      puts "Feature memory '#{args[:feature_name]}' not found"
      exit 1
    end

    puts memory.to_markdown
    puts "\n" + "="*80 + "\n"
    puts "Current Status: #{memory.status}"
    
    if current = memory.current_step
      puts "Last Action: #{current[:action]}"
      puts "Timestamp: #{current[:timestamp]}"
      puts "Code Reference: #{current[:code_ref]}" if current[:code_ref]
    end
  end

  desc "Generate report for all features"
  task report: :environment do
    features = FeatureMemories::ApplicationFeatureMemory.all
    
    if features.empty?
      puts "No feature memories found"
      exit
    end

    puts "\nFeature Memory Report"
    puts "=" * 80
    puts sprintf("%-30s %-15s %-35s", "Feature", "Status", "Last Action")
    puts "-" * 80

    features.each do |feature|
      status = feature.status
      current = feature.current_step
      last_action = current ? current[:action] : "No actions recorded"
      
      puts sprintf("%-30s %-15s %-35s", 
                   feature.feature_id, 
                   status,
                   last_action.truncate(35))
    end
    
    puts "\nTotal features: #{features.count}"
  end

  private

  def show_all_status
    features = FeatureMemories::ApplicationFeatureMemory.all
    
    if features.empty?
      puts "No feature memories found"
      return
    end

    features.each do |feature|
      puts "\n#{feature.feature_id}: #{feature.status}"
      if current = feature.current_step
        puts "  Last action: #{current[:action]}"
        puts "  Timestamp: #{current[:timestamp]}"
      end
    end
  end

  def show_feature_status(feature_name)
    memory = ApplicationFeatureMemory.find(feature_name)
    
    unless memory
      puts "Feature memory '#{feature_name}' not found"
      return
    end

    spec = memory.feature_data[:spec] || {}
    log = memory.feature_data[:implementation_log] || []
    
    puts "\nFeature: #{memory.feature_id}"
    puts "Status: #{memory.status}"
    puts "Description: #{spec[:description]}"
    puts "Requested by: #{spec[:requested_by]}"
    puts "\nImplementation Progress:"
    
    log.each do |step|
      status_icon = case step[:status]
                    when :completed then "✓"
                    when :in_progress then "→"
                    when :failed then "✗"
                    else "○"
                    end
      
      puts "#{status_icon} [#{step[:timestamp]}] #{step[:action]}"
      puts "  Code: #{step[:code_ref]}" if step[:code_ref]
      puts "  Challenge: #{step[:challenge]}" if step[:challenge]
    end
  end
end

# Backwards compatibility - remove after migration
namespace :idm do
  desc "Find IDM files related to a keyword or feature"
  task :find, [:query] => :environment do |_t, args|
    query = args[:query]
    
    if query.blank?
      puts "Usage: rails idm:find[keyword]"
      puts "Example: rails idm:find[linkedin]"
      exit 1
    end
    
    puts "\n🔍 Searching for IDM files related to '#{query}'...\n\n"
    
    # Search for feature memory files
    feature_memories = Dir.glob(Rails.root.join("app/services/feature_memories/*.rb"))
    matches = []
    
    feature_memories.each do |file|
      next if file.include?("application_feature_memory")
      
      content = File.read(file)
      feature_id = content.match(/FEATURE_ID\s*=\s*["']([^"']+)["']/i)&.[](1)
      
      # Check if filename or content matches query
      if file.downcase.include?(query.downcase) || 
         content.downcase.include?(query.downcase) ||
         feature_id&.downcase&.include?(query.downcase)
        
        matches << {
          file: file,
          feature_id: feature_id,
          description: extract_description(content)
        }
      end
    end
    
    if matches.empty?
      puts "No IDM files found matching '#{query}'"
    else
      puts "Found #{matches.count} IDM file(s):\n\n"
      
      matches.each do |match|
        puts "📁 #{match[:file].gsub(Rails.root.to_s + '/', '')}"
        puts "   Feature ID: #{match[:feature_id]}"
        puts "   Description: #{match[:description]}"
        puts ""
      end
      
      puts "\nTo check status: rails idm:status[#{matches.first[:feature_id]}]"
      puts "To view details: rails idm:show[#{matches.first[:feature_id]}]"
    end
  end
  
  desc "Show current status of an IDM feature"
  task :status, [:feature_id] => :environment do |_t, args|
    feature_id = args[:feature_id]
    
    if feature_id.blank?
      puts "Usage: rails idm:status[feature_id]"
      puts "Example: rails idm:status[linkedin_discovery_internal]"
      exit 1
    end
    
    # Use the find method from ApplicationFeatureMemory
    memory = FeatureMemories::ApplicationFeatureMemory.find(feature_id)
    
    if memory.nil?
      puts "❌ Feature '#{feature_id}' not found"
      puts "Use 'rails idm:list' to see all available features"
      exit 1
    end
    
    puts "\n📊 IDM Status for #{feature_id}"
    puts "=" * 60
    
    # Show plan status
    plan_status = memory.plan_status
    puts "\n📋 Implementation Plan:"
    puts "Progress: #{plan_status[:completion_percentage]}% Complete (#{plan_status[:completed]}/#{plan_status[:total]} tasks)"
    
    # Show current tasks
    current_tasks = memory.current_tasks
    if current_tasks.any?
      puts "\n🚀 Current Tasks:"
      current_tasks.each do |task|
        puts "- #{task[:description]} (#{task[:status]})"
      end
    end
    
    # Show recent activity
    recent_logs = memory.feature_data[:implementation_log]&.last(3) || []
    if recent_logs.any?
      puts "\n📝 Recent Activity:"
      recent_logs.each do |log|
        time = log[:timestamp] || "Unknown time"
        puts "- #{time}: #{log[:action]}"
      end
    end
    
    puts "\nFor full details: rails idm:show[#{feature_id}]"
  end
  
  desc "List all IDM features"
  task list: :environment do
    # Load all feature memory classes
    Dir.glob(Rails.root.join("app/services/feature_memories/*.rb")).each do |file|
      require file unless file.include?("application_feature_memory")
    end
    
    features = FeatureMemories::ApplicationFeatureMemory.all
    
    if features.empty?
      puts "No IDM features found"
      exit 0
    end
    
    puts "\n📚 All IDM Features"
    puts "=" * 80
    
    features.each do |feature|
      status = feature.status
      completion = feature.plan_status[:completion_percentage]
      
      status_emoji = case status
                     when :completed then "✅"
                     when :in_progress then "🚧"
                     when :planning then "📝"
                     else "⏳"
                     end
      
      puts "\n#{status_emoji} #{feature.feature_id}"
      puts "   Description: #{feature.feature_data.dig(:spec, :description)}"
      puts "   Status: #{status} (#{completion}% complete)"
      puts "   Created: #{feature.feature_data.dig(:spec, :created_at)}"
    end
    
    puts "\n\nTotal features: #{features.count}"
  end
  
  desc "Show UI testing status for a feature"
  task :ui_status, [:feature_id] => :environment do |_t, args|
    feature_id = args[:feature_id]
    
    if feature_id.blank?
      puts "Usage: rails idm:ui_status[feature_id]"
      puts "Example: rails idm:ui_status[linkedin_discovery_internal]"
      exit 1
    end
    
    memory = FeatureMemories::ApplicationFeatureMemory.find(feature_id)
    
    if memory.nil?
      puts "❌ Feature '#{feature_id}' not found"
      exit 1
    end
    
    ui_status = memory.ui_testing_status
    
    puts "\n🧪 UI Testing Status for #{feature_id}"
    puts "=" * 60
    
    case ui_status[:status]
    when :no_tests
      puts "❌ No UI tests defined"
      puts "\nRecommendation: Add UI testing block to feature memory"
    when :passed
      puts "✅ All UI tests passing (#{ui_status[:passed]}/#{ui_status[:total]})"
      puts "Coverage: #{ui_status[:pass_percentage]}% (Requirement: #{ui_status[:coverage_requirement]}%)"
    when :failed
      puts "❌ UI tests failing (#{ui_status[:failed]} failures)"
      puts "Passed: #{ui_status[:passed]}/#{ui_status[:total]} (#{ui_status[:pass_percentage]}%)"
    when :incomplete
      puts "⚠️  UI tests incomplete"
      puts "Status: #{ui_status[:passed]} passed, #{ui_status[:pending]} pending, #{ui_status[:in_progress]} in progress"
    when :insufficient_coverage
      puts "⚠️  Insufficient test coverage: #{ui_status[:pass_percentage]}% (Requirement: #{ui_status[:coverage_requirement]}%)"
    end
    
    # Show scenarios by type
    scenarios_by_type = memory.ui_test_scenarios_by_type
    if scenarios_by_type.any?
      puts "\n📋 Test Scenarios by Type:"
      scenarios_by_type.each do |type, scenarios|
        status_counts = scenarios.group_by { |s| s[:status] }.transform_values(&:count)
        puts "  #{type.to_s.humanize}: #{scenarios.count} scenarios"
        puts "    #{status_counts.map { |status, count| "#{status}: #{count}" }.join(', ')}"
      end
    end
    
    # Show blockers if any
    blockers = memory.ui_testing_blockers
    if blockers.any?
      puts "\n🚫 Completion Blockers:"
      blockers.each { |blocker| puts "  • #{blocker}" }
    end
    
    puts "\nFor full status: rails idm:completion_status[#{feature_id}]"
  end
  
  desc "Show comprehensive completion status including UI tests"
  task :completion_status, [:feature_id] => :environment do |_t, args|
    feature_id = args[:feature_id]
    
    if feature_id.blank?
      puts "Usage: rails idm:completion_status[feature_id]"
      exit 1
    end
    
    memory = FeatureMemories::ApplicationFeatureMemory.find(feature_id)
    
    if memory.nil?
      puts "❌ Feature '#{feature_id}' not found"
      exit 1
    end
    
    status_report = memory.completion_status_report
    
    puts "\n📊 Completion Status Report for #{feature_id}"
    puts "=" * 70
    
    puts "\n🎯 Overall Status: #{status_report[:overall_status]}"
    puts "Ready for Completion: #{status_report[:ready_for_completion] ? '✅ Yes' : '❌ No'}"
    
    # Implementation Plan Status
    plan = status_report[:implementation_plan]
    puts "\n📋 Implementation Plan:"
    puts "  Progress: #{plan[:completion_percentage]}% (#{plan[:completed]}/#{plan[:total]} tasks)"
    puts "  Remaining: #{plan[:pending]} pending, #{plan[:in_progress]} in progress"
    
    # UI Testing Status  
    ui = status_report[:ui_testing]
    puts "\n🧪 UI Testing:"
    puts "  Status: #{ui[:status]}"
    if ui[:total] > 0
      puts "  Coverage: #{ui[:pass_percentage]}% (#{ui[:passed]}/#{ui[:total]} tests)"
      puts "  Required: #{ui[:coverage_requirement]}% minimum"
      puts "  Mandatory: #{ui[:mandatory_completion] ? 'Yes' : 'No'}"
    end
    
    # Blockers
    if status_report[:blockers].any?
      puts "\n🚫 Completion Blockers:"
      status_report[:blockers].each { |blocker| puts "  • #{blocker}" }
    else
      puts "\n✅ No blockers - ready for completion!"
    end
  end
  
  desc "Update UI test status"
  task :update_ui_test, [:feature_id, :scenario_id, :status] => :environment do |_t, args|
    feature_id = args[:feature_id]
    scenario_id = args[:scenario_id] 
    status = args[:status]&.to_sym
    
    if [feature_id, scenario_id, status].any?(&:blank?)
      puts "Usage: rails idm:update_ui_test[feature_id,scenario_id,status]"
      puts "Status options: pending, in_progress, passed, failed, skipped"
      exit 1
    end
    
    unless [:pending, :in_progress, :passed, :failed, :skipped].include?(status)
      puts "Invalid status. Options: pending, in_progress, passed, failed, skipped"
      exit 1
    end
    
    memory = FeatureMemories::ApplicationFeatureMemory.find(feature_id)
    
    if memory.nil?
      puts "❌ Feature '#{feature_id}' not found"
      exit 1
    end
    
    if memory.update_ui_test_status(scenario_id, status)
      puts "✅ Updated UI test scenario #{scenario_id} to #{status}"
    else
      puts "❌ Failed to update UI test scenario - scenario not found"
    end
  end

  desc "Quick check: Show IDM instructions for agents"
  task instructions: :environment do
    puts <<~INSTRUCTIONS
    
    🤖 IDM Instructions for AI Agents
    ================================
    
    When working on any feature in this codebase:
    
    1. CHECK FOR IDM FILES:
       - Look in app/services/feature_memories/ for feature documentation
       - Search code files for "Feature tracked by IDM:" comments
       - Run: rails idm:find[feature_name]
    
    2. READ PROJECT DOCUMENTATION:
       - Always read /Users/benjamin/Documents/Projects/b2b/CLAUDE.md first
       - Read docs/IDM_RULES.md for complete IDM guidelines
       - Follow the IDM Communication Protocol
       - Update IDM logs when making changes
    
    3. BEFORE MAKING CHANGES:
       - Check IDM status: rails idm:status[feature_id]
       - Check UI testing status: rails idm:ui_status[feature_id]
       - Show plan progress to user
       - Update task status when starting work
    
    4. DURING DEVELOPMENT:
       - Add UI testing scenarios to feature memory
       - Create comprehensive test coverage (happy path, edge cases, errors)
       - Update UI test status as tests are written and executed
    
    5. AFTER MAKING CHANGES:
       - Update implementation_log in the IDM file
       - Document decisions and code references
       - Update UI test execution results
       - Show IDM updates to user
    
    6. BEFORE COMPLETION:
       - Verify all UI tests pass: rails idm:completion_status[feature_id]
       - Ensure test coverage meets requirements (90%+ default)
       - No UI testing blockers remaining
    
    Example workflow:
       rails idm:find[linkedin]          # Find related IDM files
       rails idm:status[feature_id]      # Check current status
       rails idm:ui_status[feature_id]   # Check UI testing status
       # Make your changes...
       # Add UI testing scenarios
       # Update IDM file implementation_log
       rails idm:completion_status[feature_id]  # Final status check
    
    INSTRUCTIONS
  end
  
  private
  
  def extract_description(content)
    match = content.match(/description\s+["']([^"']+)["']/i)
    match ? match[1] : "No description"
  end
end

namespace :fm do
  desc "Migrate old feature memory files to new IDM system"
  task migrate: :environment do
    old_dir = Rails.root.join("docs/features")
    
    unless Dir.exist?(old_dir)
      puts "No old feature memory files found"
      exit
    end

    migrated = 0
    Dir.glob(old_dir.join("*.md")).each do |file|
      next if File.basename(file) == "templates"
      
      feature_name = File.basename(file, ".md")
      next if feature_name == "feature_template"
      
      puts "Migrating #{feature_name}..."
      
      # Generate new feature memory class
      system("rails generate feature_memory #{feature_name}")
      
      # TODO: Parse markdown and populate the new class
      # This would require parsing the old format and converting it
      
      migrated += 1
    end
    
    puts "\nMigrated #{migrated} feature memories"
    puts "Old files preserved in #{old_dir}"
    puts "Review and update the generated classes in app/services/feature_memories/"
  end
end