# frozen_string_literal: true

namespace :financials do
  desc 'Update financial data for a sample of companies'
  task sample: :environment do
    sample_size = ENV.fetch('SAMPLE_SIZE', 5).to_i
    
    companies = Company.needs_financial_update.limit(sample_size)
    
    if companies.empty?
      puts "No companies need financial updates."
      next
    end
    
    puts "Updating financial data for #{companies.size} sample companies..."
    
    companies.each do |company|
      puts "  - #{company.company_name} (##{company.id}, #{company.registration_number})"
      CompanyFinancialsUpdater.new(company).call
    end
    
    puts "\nSample update complete!"
  end
  
  desc 'Queue all companies for financial data update'
  task queue_all: :environment do
    batch_size = ENV.fetch('BATCH_SIZE', 1000).to_i
    limit = ENV['LIMIT']&.to_i
    
    scope = Company.needs_financial_update
    total = limit ? [scope.count, limit].min : scope.count
    
    if total.zero?
      puts "No companies need financial updates."
      next
    end
    
    puts "Queuing updates for #{total} companies in batches of #{batch_size}..."
    
    processed = 0
    scope.find_in_batches(batch_size: batch_size) do |batch|
      batch = batch.limit(limit - processed) if limit && (processed + batch.size > limit)
      
      batch.each do |company|
        UpdateCompanyFinancialsWorker.perform_async(company.id)
        processed += 1
        print "." if (processed % 100).zero?
      end
      
      break if limit && processed >= limit
    end
    
    puts "\n\nQueued updates for #{processed} companies."
  end
  
  desc 'Show companies that need financial data updates'
  task show_pending: :environment do
    total = Company.count
    needs_update = Company.needs_financial_update
    recently_updated = Company.where("last_financial_data_fetch_at > ?", 1.day.ago)
    old_updates = Company.where("last_financial_data_fetch_at <= ?", 1.day.ago).where.not(last_financial_data_fetch_at: nil)
    
    puts "\nPending Financial Data Updates"
    puts "=" * 60
    puts "Total Companies: #{total}"
    puts "Needs Update: #{needs_update.count} (#{percentage(needs_update.count, total)}%)"
    puts "Recently Updated (< 24h): #{recently_updated.count} (#{percentage(recently_updated.count, total)}%)"
    puts "Old Updates (> 24h): #{old_updates.count} (#{percentage(old_updates.count, total)}%)"
    
    sample = needs_update.order(:updated_at).limit(5)
    
    if sample.any?
      puts "\nSample of Companies Needing Updates:"
      sample.each do |company|
        last_updated = company.last_financial_data_fetch_at ? "Last: #{company.last_financial_data_fetch_at}" : "Never updated"
        puts "  - #{company.company_name} (##{company.id}, #{company.registration_number}) - #{last_updated}"
      end
    end
    
    show_kafka_status('company_financials', 'financials_consumer')
  end
  
  desc 'Show financial data update statistics'
  task stats: :environment do
    total = Company.count
    with_data = Company.with_financial_data
    without_data = Company.without_financial_data
    successful = Company.where(financial_data_status: 'success')
    failed = Company.where(financial_data_status: 'failed')
    
    # Get performance metrics (assuming you have a service_audit_logs table)
    avg_duration = 0
    min_duration = 0
    max_duration = 0
    recent_success_rate = 0
    
    if defined?(ServiceAuditLog)
      logs = ServiceAuditLog.where(service_name: 'company_financials')
      successful_logs = logs.where(status: 'SUCCESS')
      failed_logs = logs.where(status: 'FAILED')
      
      if successful_logs.any?
        avg_duration = successful_logs.average(:duration_ms).to_i
        min_duration = successful_logs.minimum(:duration_ms).to_i
        max_duration = successful_logs.maximum(:duration_ms).to_i
      end
      
      recent_logs = logs.where('created_at > ?', 24.hours.ago)
      if recent_logs.any?
        recent_success_rate = (recent_logs.where(status: 'SUCCESS').count.to_f / recent_logs.count * 100).round(2)
      end
    end
    
    puts "\nFinancial Data Update Statistics"
    puts "=" * 60
    
    puts "\nCompanies:"
    puts "  Total: #{total}"
    puts "  With Financial Data: #{with_data.count} (#{percentage(with_data.count, total)}%)"
    puts "  Without Financial Data: #{without_data.count} (#{percentage(without_data.count, total)}%)"
    puts "  Successfully Updated: #{successful.count} (#{percentage(successful.count, total)}%)"
    puts "  Failed Updates: #{failed.count} (#{percentage(failed.count, total)}%)"
    
    if defined?(ServiceAuditLog)
      puts "\nService Audit Logs:"
      puts "  Total Logs: #{logs.count}"
      puts "  Successful: #{successful_logs.count} (#{percentage(successful_logs.count, logs.count)}%)"
      puts "  Failed: #{failed_logs.count} (#{percentage(failed_logs.count, logs.count)}%)"
    end
    
    puts "\nPerformance:"
    puts "  Average Duration: #{avg_duration}ms"
    puts "  Min Duration: #{min_duration}ms"
    puts "  Max Duration: #{max_duration}ms"
    
    puts "\nRecent Activity (24h):"
    puts "  Success Rate: #{recent_success_rate}%"
    
    show_kafka_status('company_financials', 'financials_consumer')
  end
  
  private
  
  def self.percentage(part, total)
    return 0 if total.zero?
    ((part.to_f / total) * 100).round(2)
  end
  
  def self.show_kafka_status(topic, consumer_group)
    begin
      kafka = Kafka.new(
        ENV.fetch('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092').split(','),
        client_id: 'b2b_services',
        logger: Rails.logger
      )
      
      lag = kafka.consumer_group_offsets(consumer_group)
      topic_lag = lag[topic]&.values&.sum || 0
      
      puts "\nKafka Status:"
      puts "  Topic: #{topic}"
      puts "  Consumer Group: #{consumer_group}"
      puts "  Consumer Lag: #{topic_lag} messages"
    rescue => e
      puts "\nError getting Kafka stats: #{e.message}"
    end
  end
end
