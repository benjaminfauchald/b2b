# frozen_string_literal: true

namespace :financials do
  desc "Update financial data for a sample of companies"
  task sample: :environment do
    sample_size = ENV.fetch("SAMPLE_SIZE", 5).to_i

    companies = Company.needs_financial_update.limit(sample_size)

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

  desc "Queue companies for financial data update"
  task :queue, [ :count ] => :environment do |_t, args|
    count = args[:count]&.to_i

    if count.nil?
      puts "Queueing all companies for financial data update..."
      companies = Company.needs_financial_update
    else
      puts "Queueing #{count} companies for financial data update..."
      companies = Company.needs_financial_update.limit(count)
    end

    if companies.empty?
      puts "No companies need financial updates."
      next
    end

    total = companies.count
    processed = 0

    companies.find_each do |company|
      begin
        CompanyFinancialsWorker.perform_async(company.id)
        processed += 1
        print "." if (processed % 100).zero?
      rescue StandardError => e
        print "x"
      end
    end

    puts "\n\nQueued #{processed} companies for financial data update."
  end

  desc "Show companies that need financial data updates"
  task show_pending: :environment do
    companies = Company.needs_financial_update

    if companies.empty?
      puts "No companies need financial updates."
      next
    end

    puts "Found #{companies.count} companies needing financial updates:"
    companies.each do |company|
      puts "  - #{company.company_name} (##{company.id}, #{company.registration_number})"
    end
  end

  desc "Show financial data update statistics"
  task stats: :environment do
    total = Company.count
    with_data = Company.with_financial_data
    without_data = Company.without_financial_data

    # Get performance metrics from service audit logs
    logs = ServiceAuditLog.where(service_name: "company_financials")
    successful_logs = logs.where(status: "success")
    failed_logs = logs.where(status: "failed")

    # Get companies that have been successfully updated
    successful_company_ids = successful_logs.where(auditable_type: "Company").distinct.pluck(:auditable_id)
    failed_company_ids = failed_logs.where(auditable_type: "Company").distinct.pluck(:auditable_id)

    puts "\nFinancial Data Update Statistics"
    puts "=" * 60

    puts "\nCompanies:"
    puts "  Total: #{total}"
    puts "  With Financial Data: #{with_data.count} (#{percentage(with_data.count, total)}%)"
    puts "  Without Financial Data: #{without_data.count} (#{percentage(without_data.count, total)}%)"
    puts "  Successfully Updated: #{successful_company_ids.count} (#{percentage(successful_company_ids.count, total)}%)"
    puts "  Failed Updates: #{failed_company_ids.count} (#{percentage(failed_company_ids.count, total)}%)"

    puts "\nService Audit Logs:"
    puts "  Total Logs: #{logs.count}"
    puts "  Successful: #{successful_logs.count} (#{percentage(successful_logs.count, logs.count)}%)"
    puts "  Failed: #{failed_logs.count} (#{percentage(failed_logs.count, logs.count)}%)"

    # Show recent performance
    recent_logs = logs.where("created_at > ?", 24.hours.ago)
    if recent_logs.any?
      avg_duration = recent_logs.where.not(execution_time_ms: nil).average(:execution_time_ms)&.to_i || 0
      min_duration = recent_logs.where.not(execution_time_ms: nil).minimum(:execution_time_ms)&.to_i || 0
      max_duration = recent_logs.where.not(execution_time_ms: nil).maximum(:execution_time_ms)&.to_i || 0

      puts "\nRecent Performance (24h):"
      puts "  Tests Run: #{recent_logs.count}"
      puts "  Success Rate: #{percentage(recent_logs.where(status: 'success').count, recent_logs.count)}%"
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
