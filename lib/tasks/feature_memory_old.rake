namespace :feature_memory do
  desc "Create a new feature memory file"
  task :create, [ :name ] => :environment do |t, args|
    name = args[:name]
    if name.blank?
      puts "Error: Feature name is required"
      puts "Usage: rake feature_memory:create[feature_name]"
      exit 1
    end

    system("./bin/feature-memory create #{name}")
  end

  desc "List all feature memory files"
  task list: :environment do
    system("./bin/feature-memory list")
  end

  desc "Show status summary of all features"
  task status: :environment do
    system("./bin/feature-memory status")
  end

  desc "Update last modified date for a feature"
  task :update, [ :name ] => :environment do |t, args|
    name = args[:name]
    if name.blank?
      puts "Error: Feature name is required"
      puts "Usage: rake feature_memory:update[feature_name]"
      exit 1
    end

    system("./bin/feature-memory update #{name}")
  end

  desc "Mark a feature as completed"
  task :complete, [ :name ] => :environment do |t, args|
    name = args[:name]
    if name.blank?
      puts "Error: Feature name is required"
      puts "Usage: rake feature_memory:complete[feature_name]"
      exit 1
    end

    system("./bin/feature-memory complete #{name}")
  end

  desc "Validate all feature memory files"
  task validate: :environment do
    features_dir = Rails.root.join("docs", "features")
    template_file = features_dir.join("templates", "feature_template.md")

    unless File.exist?(template_file)
      puts "Error: Template file not found: #{template_file}"
      exit 1
    end

    files = Dir.glob(features_dir.join("*.md")).reject { |f| f.include?("templates/") }

    if files.empty?
      puts "No feature memory files found."
      return
    end

    puts "Validating feature memory files..."
    puts "=" * 50

    valid_count = 0
    invalid_count = 0

    files.each do |file|
      content = File.read(file)
      name = File.basename(file, ".md")

      # Check for required sections
      required_sections = [
        "## Feature Information",
        "## Overview",
        "## Requirements",
        "## Technical Plan",
        "## Current Progress",
        "## Technical Decisions",
        "## Code References",
        "## Test Plan",
        "## Conversation Context"
      ]

      missing_sections = required_sections.select { |section| !content.include?(section) }

      if missing_sections.empty?
        puts "✓ #{name} - Valid"
        valid_count += 1
      else
        puts "✗ #{name} - Missing: #{missing_sections.join(', ')}"
        invalid_count += 1
      end
    end

    puts "=" * 50
    puts "Valid: #{valid_count}, Invalid: #{invalid_count}"

    if invalid_count > 0
      puts "Please update invalid files to include all required sections."
      exit 1
    end
  end

  desc "Generate feature memory report"
  task report: :environment do
    features_dir = Rails.root.join("docs", "features")
    files = Dir.glob(features_dir.join("*.md")).reject { |f| f.include?("templates/") }

    if files.empty?
      puts "No feature memory files found."
      return
    end

    puts "Feature Memory Report"
    puts "=" * 60
    puts "Generated: #{Time.current}"
    puts

    status_counts = Hash.new(0)
    features_by_status = Hash.new { |h, k| h[k] = [] }

    files.each do |file|
      content = File.read(file)
      name = File.basename(file, ".md").gsub("_", " ").split.map(&:capitalize).join(" ")

      # Extract status
      status_match = content.match(/- \*\*Status\*\*: (.+)/)
      status = status_match ? status_match[1].strip : "unknown"

      # Extract last updated
      updated_match = content.match(/- \*\*Last Updated\*\*: (.+)/)
      last_updated = updated_match ? updated_match[1].strip : "unknown"

      # Extract current step
      step_match = content.match(/\*\*Current Step\*\*: (.+)/)
      current_step = step_match ? step_match[1].strip : "unknown"

      status_counts[status] += 1
      features_by_status[status] << {
        name: name,
        last_updated: last_updated,
        current_step: current_step
      }
    end

    puts "Status Summary:"
    puts "-" * 30
    status_counts.each do |status, count|
      puts "#{status.capitalize.ljust(15)} #{count}"
    end
    puts "-" * 30
    puts "Total: #{files.length}"
    puts

    features_by_status.each do |status, features|
      puts "#{status.capitalize} Features:"
      puts "-" * 40
      features.each do |feature|
        puts "• #{feature[:name]}"
        puts "  Last Updated: #{feature[:last_updated]}"
        puts "  Current Step: #{feature[:current_step]}"
        puts
      end
    end
  end
end
