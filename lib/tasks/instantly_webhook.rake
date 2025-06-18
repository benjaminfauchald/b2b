namespace :instantly_webhook do
  desc "Show Instantly webhook statistics"
  task stats: :environment do
    puts "\nInstantly Webhook Statistics"
    puts "=" * 60

    # Get all webhook logs
    logs = ServiceAuditLog.where(service_name: "instantly_webhook")
    total_logs = logs.count
    success_logs = logs.successful.count
    failed_logs = logs.failed.count

    # Calculate success rate
    success_rate = total_logs.positive? ? (success_logs * 100.0 / total_logs).round(2) : 0

    # Get performance metrics
    avg_duration = logs.successful.average(:duration_ms).to_i
    min_duration = logs.successful.minimum(:duration_ms)
    max_duration = logs.successful.maximum(:duration_ms)

    # Recent activity (last 24 hours)
    recent_logs = logs.where("started_at > ?", 24.hours.ago)
    recent_success = recent_logs.successful.count
    recent_total = recent_logs.count
    recent_success_rate = recent_total.positive? ? (recent_success * 100.0 / recent_total).round(2) : 0

    # Error analysis
    error_types = logs.failed.group(:error_message).count.sort_by { |_, count| -count }

    puts "\nOverall Statistics:"
    puts "  Total Webhooks: #{total_logs}"
    puts "  Successful: #{success_logs} (#{success_rate}%)"
    puts "  Failed: #{failed_logs} (#{100 - success_rate}%)"

    puts "\nPerformance:"
    puts "  Average Duration: #{avg_duration}ms"
    puts "  Min Duration: #{min_duration}ms"
    puts "  Max Duration: #{max_duration}ms"

    puts "\nRecent Activity (24h):"
    puts "  Webhooks Received: #{recent_total}"
    puts "  Success Rate: #{recent_success_rate}%"

    if error_types.any?
      puts "\nTop Error Types:"
      error_types.first(5).each do |error, count|
        puts "  #{error}: #{count} occurrences"
      end
    end

    # Check for potential issues
    puts "\nPotential Issues:"

    # Check for high failure rate in last hour
    last_hour = logs.where("started_at > ?", 1.hour.ago)
    if last_hour.any?
      last_hour_rate = (last_hour.failed.count * 100.0 / last_hour.count).round(2)
      if last_hour_rate > 20
        puts "  ⚠️ High failure rate in last hour: #{last_hour_rate}%"
      end
    end

    # Check for slow responses
    if avg_duration > 1000
      puts "  ⚠️ Slow average response time: #{avg_duration}ms"
    end

    # Check for repeated errors
    if error_types.any? { |_, count| count > 5 }
      puts "  ⚠️ Multiple repeated errors detected"
    end
  end

  desc "Clean old webhook logs (default: 90 days)"
  task clean: :environment do
    days = ENV["DAYS"]&.to_i || 90
    puts "Cleaning Instantly webhook logs older than #{days} days..."
    deleted_count = ServiceAuditLog.where(service_name: "instantly_webhook")
                                 .where("created_at < ?", days.days.ago)
                                 .delete_all
    puts "Deleted #{deleted_count} old webhook log records."
  end
end
