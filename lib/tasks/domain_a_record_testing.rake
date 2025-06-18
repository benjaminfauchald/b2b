# frozen_string_literal: true

namespace :domain_a_record_testing do
  desc "Test A records for a sample of domains"
  task sample: :environment do
    sample_size = ENV.fetch("SAMPLE_SIZE", 5).to_i

    domains = Domain.needs_service("domain_a_record_testing").limit(sample_size)

    if domains.empty?
      puts "No domains need A record testing."
      next
    end

    puts "Testing A records for #{domains.size} sample domains..."

    domains.each do |domain|
      print "  - #{domain.domain} (##{domain.id})"

      begin
        DomainARecordTestingService.new(domain: domain).call
        print " ✓\n"
      rescue StandardError => e
        print " ✗ (#{e.message})\n"
      end
    end

    puts "\nSample testing complete!"
  end

  desc "Queue domains for A record testing"
  task :queue, [ :count ] => :environment do |_t, args|
    count = args[:count]&.to_i

    if count.nil?
      puts "Queueing all domains for A record testing..."
      domains = Domain.needs_service("domain_a_record_testing")
    else
      puts "Queueing #{count} domains for A record testing..."
      domains = Domain.needs_service("domain_a_record_testing").limit(count)
    end

    if domains.empty?
      puts "No domains need A record testing."
      next
    end

    total = domains.count
    processed = 0

    domains.find_each do |domain|
      begin
        DomainARecordTestingWorker.perform_async(domain.id)
        processed += 1
        print "." if (processed % 100).zero?
      rescue StandardError => e
        print "x"
      end
    end

    puts "\n\nQueued #{processed} domains for A record testing."
  end

  desc "Show domains that need A record testing"
  task show_pending: :environment do
    domains = Domain.needs_service("domain_a_record_testing")

    if domains.empty?
      puts "No domains need A record testing."
      next
    end

    puts "Found #{domains.count} domains needing A record testing:"
    domains.each do |domain|
      puts "  - #{domain.domain} (##{domain.id})"
    end
  end

  desc "Show A record testing statistics"
  task stats: :environment do
    total = Domain.count
    tested = Domain.where.not(www: nil).count
    untested = Domain.where(www: nil).count
    outdated = Domain.where("updated_at < ?", 1.day.ago).count

    # Get performance metrics from service audit logs
    logs = ServiceAuditLog.where(service_name: "domain_a_record_testing")
    successful = logs.where(status: "success").count
    failed = logs.where(status: "failed").count

    puts "\nA Record Testing Statistics"
    puts "=" * 60

    puts "\nDomains:"
    puts "  Total: #{total}"
    puts "  Tested: #{tested} (#{percentage(tested, total)}%)"
    puts "  Untested: #{untested} (#{percentage(untested, total)}%)"
    puts "  Outdated: #{outdated} (#{percentage(outdated, total)}%)"

    puts "\nService Audit Logs:"
    puts "  Total Logs: #{logs.count}"
    puts "  Successful: #{successful} (#{percentage(successful, logs.count)}%)"
    puts "  Failed: #{failed} (#{percentage(failed, logs.count)}%)"

    # Show recent performance
    recent_logs = logs.where("created_at > ?", 24.hours.ago)
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
