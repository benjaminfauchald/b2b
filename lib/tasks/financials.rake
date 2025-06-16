# frozen_string_literal: true

namespace :financials do
  desc 'Update financial data for a sample of companies'
  task sample: :environment do
    sample_size = ENV.fetch('SAMPLE_SIZE', 5).to_i
    
    # Find companies that need updates based on SCT audit logs
    companies = Company.joins("LEFT JOIN service_audit_logs ON service_audit_logs.auditable_id = companies.id AND service_audit_logs.auditable_type = 'Company' AND service_audit_logs.service_name = 'company_financials'")
                      .where("service_audit_logs.id IS NULL OR service_audit_logs.created_at < ?", 1.month.ago)
                      .distinct
                      .limit(sample_size)
    
    if companies.empty?
      puts "No companies need financial updates."
      next
    end
    
    puts "Updating financial data for #{companies.size} sample companies..."
    
    companies.each do |company|
      print "  - #{company.company_name} (##{company.id}, #{company.registration_number})"
      
      begin
        CompanyFinancialsService.new(company_id: company.id).call
        print " ✓\n"
      rescue StandardError => e
        print " ✗ (#{e.message})\n"
      end
    end
    
    puts "\nSample update complete!"
  end
  
  desc 'Queue all companies for financial data update'
  task queue_all: :environment do
    batch_size = ENV.fetch('BATCH_SIZE', 1000).to_i
    limit = ENV['LIMIT']&.to_i
    force = ENV['FORCE'] == 'true'
    
    scope = force ? Company.all : Company.where("http_error IS NOT NULL OR http_error IS NULL OR updated_at < ?", 1.month.ago)
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
        CompanyFinancialsService.new(company_id: company.id).call
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
    needs_update = Company.where("http_error IS NOT NULL OR http_error IS NULL OR updated_at < ?", 1.month.ago)
    
    last_month = 1.month.ago
    recently_updated = ServiceAuditLog.where(
      service_name: 'company_financials_v1',
      status: :success,
      created_at: (last_month..Time.current)
    ).count
    
    old_updates = ServiceAuditLog.where(
      service_name: 'company_financials_v1',
      status: :success,
      created_at: ..last_month
    ).count
    
    puts "\nPending Financial Data Updates"
    puts "=" * 60
    puts "Total Companies: #{total}"
    puts "Needs Update: #{needs_update.count} (#{percentage(needs_update.count, total)}%)"
    puts "Recently Updated (< 1 month): #{recently_updated} (#{percentage(recently_updated, total)}%)"
    puts "Old Updates (> 1 month): #{old_updates} (#{percentage(old_updates, total)}%)"
    
    sample = needs_update.order(:updated_at).limit(5)
    
    if sample.any?
      puts "\nSample of Companies Needing Updates:"
      sample.each do |company|
        last_updated = company.last_financial_data_fetch_at ? "Last: #{company.last_financial_data_fetch_at}" : "Never updated"
        puts "  - #{company.company_name} (##{company.id}, #{company.registration_number}) - #{last_updated}"
      end
    end
  end
  
  desc 'Show financial data update statistics'
  task stats: :environment do
    total = Company.count
    with_data = Company.with_financial_data.count
    without_data = Company.without_financial_data.count
    
    logs = ServiceAuditLog.where(service_name: 'company_financials_v1')
    successful_logs = logs.where(status: :success)
    failed_logs = logs.where(status: :failed)
    successful_logs = logs.where(status: 'success')
    failed_logs = logs.where(status: 'failed')
    
    # Calculate success rate
    success_rate = logs.any? ? (successful_logs.count.to_f / logs.count * 100).round(2) : 0
    
    # Get performance metrics
    avg_duration = successful_logs.average('EXTRACT(EPOCH FROM (completed_at - started_at) * 1000)').to_i
    min_duration = successful_logs.minimum('EXTRACT(EPOCH FROM (completed_at - started_at) * 1000)').to_i
    max_duration = successful_logs.maximum('EXTRACT(EPOCH FROM (completed_at - started_at) * 1000)').to_i
    
    # Recent activity (last 24 hours)
    recent_logs = logs.where('started_at > ?', 24.hours.ago)
    recent_success = recent_logs.where(status: 'success').count
    recent_total = recent_logs.count
    recent_success_rate = recent_total.positive? ? (recent_success.to_f / recent_total * 100).round(2) : 0
    
    puts "\nFinancial Data Update Statistics"
    puts "=" * 60
    
    puts "\nCompanies:"
    puts "  Total: #{total}"
    puts "  With Financial Data: #{with_data} (#{percentage(with_data, total)}%)"
    puts "  Without Financial Data: #{without_data} (#{percentage(without_data, total)}%)"
    
    puts "\nService Audit Logs:"
    puts "  Total Logs: #{logs.count}"
    puts "  Successful: #{successful_logs.count} (#{success_rate}%)"
    puts "  Failed: #{failed_logs.count} (#{100 - success_rate}%)"
    
    puts "\nPerformance:"
    puts "  Average Duration: #{avg_duration}ms"
    puts "  Min Duration: #{min_duration}ms"
    puts "  Max Duration: #{max_duration}ms"
    
    puts "\nRecent Activity (24h):"
    puts "  Updates Run: #{recent_total}"
    puts "  Success Rate: #{recent_success_rate}%"
  end
  
  private
  
  def self.percentage(part, total)
    return 0 if total.zero?
    ((part.to_f / total) * 100).round(2)
  end
end
