# frozen_string_literal: true

namespace :service_template do
  desc 'Run service for a sample of records'
  task sample: :environment do
    sample_size = ENV.fetch('SAMPLE_SIZE', 5).to_i
    
    records = Record.needs_service('service_template').limit(sample_size)
    
    if records.empty?
      puts "No records need processing."
      next
    end
    
    puts "Processing #{records.size} sample records..."
    
    records.each do |record|
      print "  - #{record.name} (##{record.id})"
      
      begin
        ServiceTemplateService.new(record: record).call
        print " ✓\n"
      rescue StandardError => e
        print " ✗ (#{e.message})\n"
      end
    end
    
    puts "\nSample processing complete!"
  end
  
  desc 'Queue records for processing'
  task :queue, [:count] => :environment do |_t, args|
    count = args[:count]&.to_i
    
    if count.nil?
      puts "Queueing all records for processing..."
      records = Record.needs_service('service_template')
    else
      puts "Queueing #{count} records for processing..."
      records = Record.needs_service('service_template').limit(count)
    end
    
    if records.empty?
      puts "No records need processing."
      next
    end
    
    total = records.count
    processed = 0
    
    records.find_each do |record|
      begin
        ServiceTemplateWorker.perform_async(record.id)
        processed += 1
        print "." if (processed % 100).zero?
      rescue StandardError => e
        print "x"
      end
    end
    
    puts "\n\nQueued #{processed} records for processing."
  end
  
  desc 'Show records that need processing'
  task show_pending: :environment do
    records = Record.needs_service('service_template')
    
    if records.empty?
      puts "No records need processing."
      next
    end
    
    puts "Found #{records.count} records needing processing:"
    records.each do |record|
      puts "  - #{record.name} (##{record.id})"
    end
  end
  
  desc 'Show service statistics'
  task stats: :environment do
    total = Record.count
    processed = Record.where.not(service_template_status: nil).count
    unprocessed = Record.where(service_template_status: nil).count
    outdated = Record.where('updated_at < ?', 1.day.ago).count
    
    # Get performance metrics from service audit logs
    logs = ServiceAuditLog.where(service_name: 'service_template')
    successful = logs.where(status: 'success').count
    failed = logs.where(status: 'failed').count
    
    puts "\nService Template Statistics"
    puts "=" * 60
    
    puts "\nRecords:"
    puts "  Total: #{total}"
    puts "  Processed: #{processed} (#{percentage(processed, total)}%)"
    puts "  Unprocessed: #{unprocessed} (#{percentage(unprocessed, total)}%)"
    puts "  Outdated: #{outdated} (#{percentage(outdated, total)}%)"
    
    puts "\nService Audit Logs:"
    puts "  Total Logs: #{logs.count}"
    puts "  Successful: #{successful} (#{percentage(successful, logs.count)}%)"
    puts "  Failed: #{failed} (#{percentage(failed, logs.count)}%)"
    
    # Show recent performance
    recent_logs = logs.where('created_at > ?', 24.hours.ago)
    if recent_logs.any?
      avg_duration = recent_logs.average(:duration_ms).to_i
      min_duration = recent_logs.minimum(:duration_ms).to_i
      max_duration = recent_logs.maximum(:duration_ms).to_i
      
      puts "\nRecent Performance (24h):"
      puts "  Average Duration: #{avg_duration}ms"
      puts "  Min Duration: #{min_duration}ms"
      puts "  Max Duration: #{max_duration}ms"
    end
  end
  
  private
  
  def percentage(part, total)
    return 0 if total.zero?
    ((part.to_f / total) * 100).round(2)
  end
end 