# frozen_string_literal: true

namespace :httparty do
  desc 'Find and fix HTTParty deprecation warnings in codebase'
  task fix_deprecations: :environment do
    SERVICE_NAME = 'httparty_deprecation_fixer'
    puts "🔧 Service Name: #{SERVICE_NAME}"
    puts "🔍 Scanning codebase for HTTParty deprecation issues..."
    
    # Files to check
    files_to_check = [
      'app/services/**/*.rb',
      'app/models/**/*.rb',
      'app/controllers/**/*.rb',
      'lib/**/*.rb'
    ]
    
    deprecated_patterns = [
      /response\.nil\?/,
      /if\s+response$/,
      /unless\s+response$/,
      /response\s*&&\s*response\.body/,
      /response\s*\|\|\s*\{\}/,
      /HTTParty\.(get|post|put|delete|patch)\s*\(/,
      /include\s+HTTParty/
    ]
    
    issues_found = 0
    files_checked = 0
    
    files_to_check.each do |pattern|
      Dir[pattern].each do |file_path|
        next if file_path.include?('spec/') || file_path.include?('test/') || file_path.include?('httparty_response_helper.rb')
        
        files_checked += 1
        content = File.read(file_path)
        
        # Check if file uses HTTParty
        next unless content.include?('HTTParty') || content.include?('httparty')
        
        puts "\n📄 Checking: #{file_path}"
        
        deprecated_patterns.each_with_index do |pattern, index|
          matches = content.scan(pattern)
          if matches.any?
            issues_found += matches.count
            puts "  ⚠️  Found deprecated pattern #{index + 1}: #{matches.count} occurrences"
            
            # Show line numbers
            content.lines.each_with_index do |line, line_num|
              if line.match?(pattern)
                puts "    Line #{line_num + 1}: #{line.strip}"
              end
            end
          end
        end
      end
    end
    
    puts "\n" + "="*60
    puts "📊 HTTParty Deprecation Scan Results:"
    puts "  Files checked: #{files_checked}"
    puts "  Issues found: #{issues_found}"
    
    if issues_found > 0
      puts "\n💡 Recommended fixes:"
      puts "  1. Replace 'response.nil?' with 'response.nil? || response.body.nil? || response.body.empty?'"
      puts "  2. Use the HttpartyResponseHelper module for consistent handling"
      puts "  3. Add proper error handling for empty responses"
    else
      puts "  ✅ No deprecation issues found!"
    end
  end
  
  desc 'Show HTTParty usage statistics across the codebase'
  task stats: :environment do
    puts "📊 HTTParty Usage Statistics"
    puts "="*50
    
    files_with_httparty = 0
    total_httparty_calls = 0
    services_using_httparty = []
    
    # Check all Ruby files
    Dir['app/**/*.rb', 'lib/**/*.rb'].each do |file_path|
      next if file_path.include?('spec/') || file_path.include?('test/')
      
      content = File.read(file_path)
      
      if content.include?('HTTParty') || content.include?('httparty')
        files_with_httparty += 1
        
        # Count HTTParty method calls
        httparty_calls = content.scan(/HTTParty\.(get|post|put|delete|patch)/).count
        total_httparty_calls += httparty_calls
        
        if file_path.include?('services/')
          service_name = File.basename(file_path, '.rb')
          services_using_httparty << service_name unless services_using_httparty.include?(service_name)
        end
        
        puts "📄 #{file_path}: #{httparty_calls} HTTParty calls"
      end
    end
    
    puts "\nSummary:"
    puts "  Files using HTTParty: #{files_with_httparty}"
    puts "  Total HTTParty calls: #{total_httparty_calls}"
    puts "  Services using HTTParty: #{services_using_httparty.count}"
    
    if services_using_httparty.any?
      puts "\nServices:"
      services_using_httparty.each do |service|
        puts "  • #{service}"
      end
    end
    
    puts "\n💡 Next steps:"
    puts "  • Run 'rake httparty:fix_deprecations' to find issues"
  end
end
