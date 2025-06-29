#!/usr/bin/env ruby

# Post-Sync Validation Script
# Validates data integrity after production sync
# Run automatically or manually to check sync health

require 'colorize' if Gem::Specification.find_all_by_name('colorize').any?

class SyncValidator
  def initialize
    @errors = []
    @warnings = []
    @success_count = 0
    @total_checks = 0
  end

  def validate!
    puts "\n=== Production Data Sync Validation ==="
    puts "Time: #{Time.now}"
    puts "=" * 50
    
    validate_database_connection
    validate_table_counts
    validate_foreign_keys
    validate_data_sanitization
    validate_materialized_views
    validate_sequences
    validate_service_functionality
    
    print_summary
    
    # Exit with error code if validation failed
    exit(1) if @errors.any?
  end

  private

  def check(description)
    @total_checks += 1
    print "Checking #{description}... "
    
    begin
      result = yield
      if result
        @success_count += 1
        puts colored("✓", :green)
      else
        puts colored("✗", :red)
        @errors << "Failed: #{description}"
      end
      result
    rescue => e
      puts colored("✗", :red)
      @errors << "Error in #{description}: #{e.message}"
      false
    end
  end

  def warn(description)
    print "Warning: #{description}... "
    
    begin
      result = yield
      if result
        puts colored("OK", :yellow)
      else
        puts colored("!", :yellow)
        @warnings << "Warning: #{description}"
      end
      result
    rescue => e
      puts colored("!", :yellow)
      @warnings << "Warning in #{description}: #{e.message}"
      false
    end
  end

  def validate_database_connection
    puts "\n## Database Connection"
    
    check("Rails database connection") do
      ActiveRecord::Base.connection.active?
    end
    
    check("Database is development") do
      ActiveRecord::Base.connection.current_database.include?('development')
    end
  end

  def validate_table_counts
    puts "\n## Table Record Counts"
    
    tables = %w[users companies people domains communications service_configurations service_audit_logs]
    
    tables.each do |table|
      check("#{table} has records") do
        klass = table.classify.constantize
        count = klass.count
        puts " (#{count} records)"
        count > 0
      end
    end
  end

  def validate_foreign_keys
    puts "\n## Foreign Key Integrity"
    
    check("People -> Companies relationship") do
      orphaned = Person.where.not(company_id: nil)
                       .where.not(company_id: Company.select(:id))
                       .count
      orphaned == 0
    end
    
    check("ServiceAuditLogs polymorphic relationships") do
      # Check each auditable type
      valid = true
      ServiceAuditLog.distinct.pluck(:auditable_type).each do |type|
        klass = type.constantize
        orphaned = ServiceAuditLog.where(auditable_type: type)
                                  .where.not(auditable_id: klass.select(:id))
                                  .count
        valid &&= (orphaned == 0)
      end
      valid
    end
    
    check("ServiceAuditLogs -> ServiceConfigurations") do
      orphaned = ServiceAuditLog.where.not(service_name: ServiceConfiguration.select(:service_name))
                                .count
      warn("Found #{orphaned} audit logs without configurations") if orphaned > 0
      true # Not a critical error
    end
  end

  def validate_data_sanitization
    puts "\n## Data Sanitization"
    
    check("All non-test users have sanitized passwords") do
      test_emails = ['test@test.no', 'admin@example.com']
      User.where.not(email: test_emails).all? do |user|
        # Check if password is the development password
        user.encrypted_password == '$2a$12$K2xPQbGQhXVLWszpQeGJ6.Gt8nFwKqYZcbMx8IG4u9O7hQxXyqFCa'
      end
    end
    
    check("User emails are anonymized") do
      test_emails = ['test@test.no', 'admin@example.com']
      User.where.not(email: test_emails).all? do |user|
        user.email.match?(/^user\d+@/)
      end
    end
    
    check("No production IPs in user records") do
      User.where.not(current_sign_in_ip: nil).count == 0 &&
      User.where.not(last_sign_in_ip: nil).count == 0
    end
    
    check("Person emails are sanitized") do
      Person.where.not(email: nil).all? do |person|
        person.email.match?(/^person\d+@example\.com$/)
      end
    end
  end

  def validate_materialized_views
    puts "\n## Materialized Views"
    
    warn("service_performance_stats exists") do
      ActiveRecord::Base.connection.execute(
        "SELECT 1 FROM pg_matviews WHERE matviewname = 'service_performance_stats'"
      ).any?
    end
    
    warn("latest_service_runs exists") do
      ActiveRecord::Base.connection.execute(
        "SELECT 1 FROM pg_matviews WHERE matviewname = 'latest_service_runs'"
      ).any?
    end
  end

  def validate_sequences
    puts "\n## PostgreSQL Sequences"
    
    tables_with_id = %w[users companies people domains communications service_configurations service_audit_logs]
    
    tables_with_id.each do |table|
      check("#{table} sequence is valid") do
        result = ActiveRecord::Base.connection.execute(
          "SELECT last_value FROM #{table}_id_seq"
        ).first
        
        last_value = result['last_value'].to_i
        max_id = ActiveRecord::Base.connection.execute(
          "SELECT COALESCE(MAX(id), 0) FROM #{table}"
        ).first.values.first.to_i
        
        last_value >= max_id
      end
    end
  end

  def validate_service_functionality
    puts "\n## Service Functionality"
    
    check("Can authenticate test user") do
      user = User.find_by(email: 'test@test.no')
      user.present? && user.valid_password?('CodemyFTW2')
    end
    
    check("Can authenticate admin user") do
      user = User.find_by(email: 'admin@example.com')
      user.present? && user.valid_password?('CodemyFTW2')
    end
    
    warn("ActiveStorage configured") do
      ActiveStorage::Blob.service.present?
    end
  end

  def print_summary
    puts "\n" + "=" * 50
    puts "Validation Summary"
    puts "=" * 50
    
    puts "Total checks: #{@total_checks}"
    puts colored("Successful: #{@success_count}", :green)
    
    if @errors.any?
      puts colored("\nErrors (#{@errors.count}):", :red)
      @errors.each { |e| puts "  - #{e}" }
    end
    
    if @warnings.any?
      puts colored("\nWarnings (#{@warnings.count}):", :yellow)
      @warnings.each { |w| puts "  - #{w}" }
    end
    
    if @errors.empty?
      puts colored("\n✓ All validations passed!", :green)
    else
      puts colored("\n✗ Validation failed with #{@errors.count} errors", :red)
    end
  end

  def colored(text, color)
    if defined?(Colorize)
      text.colorize(color)
    else
      text
    end
  end
end

# Run validation if called directly
if __FILE__ == $0
  validator = SyncValidator.new
  validator.validate!
end