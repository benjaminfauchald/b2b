namespace :service_audit do
  desc "Show service performance statistics"
  task stats: :environment do
    stats = ServicePerformanceStat.all.order(:service_name)
    
    if stats.empty?
      puts "No service performance data available."
      next
    end
    
    puts "\n" + "="*80
    puts "SERVICE PERFORMANCE STATISTICS"
    puts "="*80
    
    stats.each do |stat|
      puts "\nService: #{stat.service_name}"
      puts "  Total Runs: #{stat.total_runs}"
      puts "  Success Rate: #{stat.success_rate_percent}%"
      puts "  Avg Duration: #{stat.avg_duration_ms}ms"
      puts "  Date Range: #{stat.first_run_at.strftime('%Y-%m-%d')} to #{stat.last_run_at.strftime('%Y-%m-%d')}"
    end
    
    puts "\n" + "="*80
  end

  desc "Clean old audit logs (default: 90 days)"
  task clean: :environment do
    days = ENV['DAYS']&.to_i || 90
    
    puts "Cleaning audit logs older than #{days} days..."
    deleted_count = ServiceAuditLog.cleanup_old_logs(days)
    puts "Deleted #{deleted_count} old audit log records."
  end
  
  desc "Run a specific service"
  task :run_service, [:service_name] => :environment do |task, args|
    service_name = args[:service_name]
    
    if service_name.blank?
      puts "Usage: rake service_audit:run_service[service_name]"
      puts "Available services:"
      ServiceConfiguration.active.pluck(:service_name).each do |name|
        puts "  - #{name}"
      end
      exit 1
    end
    
    config = ServiceConfiguration.find_by(service_name: service_name)
    if config.nil?
      puts "Service configuration not found for: #{service_name}"
      exit 1
    end
    
    unless config.active?
      puts "Service is not active: #{service_name}"
      exit 1
    end
    
    puts "Running service: #{service_name}"
    
    case service_name
    when 'user_enhancement_v1'
      result = UserEnhancementService.new.call
      puts "User enhancement completed: #{result}"
    when 'domain_dns_testing_v1'
      result = DomainTestingService.new.call
      puts "Domain DNS testing completed: #{result}"
    else
      puts "Service implementation not found. Please implement the service class."
    end
  end
  
  desc "Show records needing refresh"
  task refresh_needed: :environment do
    records = ActiveRecord::Base.connection.execute(
      "SELECT * FROM records_needing_refresh WHERE needs_refresh = true LIMIT 20"
    )
    
    if records.count == 0
      puts "No records currently need refresh."
      return
    end
    
    puts "\nRecords needing refresh:"
    puts "-" * 60
    
    records.each do |record|
      puts "#{record['auditable_type']} ##{record['auditable_id']} - #{record['service_name']}"
      last_run = record['last_successful_run'] ? 
        Time.parse(record['last_successful_run']).strftime('%Y-%m-%d %H:%M') : 
        'Never'
      puts "  Last run: #{last_run}"
    end
    
    puts "\nShowing first 20 records. Total may be higher."
  end
  
  desc "Show service configurations"
  task configs: :environment do
    configs = ServiceConfiguration.all.order(:service_name)
    
    if configs.empty?
      puts "No service configurations found."
      return
    end
    
    puts "\nService Configurations:"
    puts "=" * 80
    
    configs.each do |config|
      status = config.active? ? "ACTIVE" : "INACTIVE"
      puts "\n#{config.service_name} [#{status}]"
      puts "  Refresh Interval: #{config.refresh_interval_hours} hours"
      puts "  Batch Size: #{config.batch_size}"
      puts "  Retry Attempts: #{config.retry_attempts}"
      puts "  Dependencies: #{config.depends_on_services.join(', ')}" if config.depends_on_services.any?
      
      # Show Kafka configuration if available
      if config.settings['kafka_topic'].present?
        puts "  Kafka Topic: #{config.settings['kafka_topic']}"
        puts "  Consumer Group: #{config.settings['kafka_consumer_group']}"
      end
    end
  end

  desc "Run domain DNS testing for untested domains"
  task test_domains: :environment do
    puts "Starting domain DNS testing service..."
    result = DomainTestingService.new.call
    
    puts "\nDomain DNS Testing Results:"
    puts "  Processed: #{result[:processed]} domains"
    puts "  Successful: #{result[:successful]} domains"
    puts "  Failed: #{result[:failed]} domains"
    puts "  Errors: #{result[:errors]} domains"
    
    if result[:processed] == 0
      puts "\nNo domains needed testing at this time."
    end
  end

  desc "Show domain testing statistics"
  task domain_stats: :environment do
    total_domains = Domain.count
    untested = Domain.untested.count
    active = Domain.dns_active.count
    inactive = Domain.dns_inactive.count
    
    puts "\nDomain Testing Statistics:"
    puts "=" * 50
    puts "  Total Domains: #{total_domains}"
    puts "  Untested (dns: nil): #{untested}"
    puts "  Active DNS (dns: true): #{active}"
    puts "  Inactive DNS (dns: false): #{inactive}"
    
    if total_domains > 0
      tested_percentage = ((total_domains - untested) * 100.0 / total_domains).round(2)
      active_percentage = (active * 100.0 / total_domains).round(2)
      puts "\n  Testing Coverage: #{tested_percentage}%"
      puts "  Active DNS Rate: #{active_percentage}%"
    end
    
    # Show recent DNS testing activity
    recent_logs = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1')
                                .where('created_at > ?', 24.hours.ago)
    
    if recent_logs.any?
      puts "\n  Recent Activity (24h): #{recent_logs.count} DNS tests"
      puts "  Success Rate: #{(recent_logs.successful.count * 100.0 / recent_logs.count).round(2)}%"
    end
    
    # Show Kafka consumer lag
    begin
      kafka = Kafka.new(
        ENV.fetch('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
        client_id: 'b2b_services'
      )
      
      consumer_group = 'domain_testing_consumer'
      topic = 'domain_testing'
      
      lag = kafka.consumer_group_offsets(consumer_group)
      topic_lag = lag[topic]&.values&.sum || 0
      
      puts "\n  Kafka Consumer Lag: #{topic_lag} messages"
    rescue => e
      puts "\n  Error getting Kafka stats: #{e.message}"
    end
  end
end 