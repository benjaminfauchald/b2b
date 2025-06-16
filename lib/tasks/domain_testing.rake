require 'sidekiq/api'

namespace :domain_testing do
  desc "Test DNS for sample of domains (default: 100)"
  task :sample, [:count] => :environment do |task, args|
    count = args[:count]&.to_i || 100
    
    puts "Testing #{count} domains..."
    
    # Use a custom batch size for the sample
    service = DomainTestingService.new(batch_size: count)
    result = service.call
    
    puts "\nSample Testing Results:"
    puts "  Processed: #{result[:processed]} domains"
    puts "  Successful: #{result[:successful]} (#{(result[:successful] * 100.0 / result[:processed]).round(2)}%)"
    puts "  Failed: #{result[:failed]} (#{(result[:failed] * 100.0 / result[:processed]).round(2)}%)"
    puts "  Errors: #{result[:errors]} (#{(result[:errors] * 100.0 / result[:processed]).round(2)}%)"
    
    # Show some examples
    recent_logs = ServiceAuditLog.where(service_name: 'domain_testing')
                                .recent.limit(5)
    
    puts "\nSample Results:"
    recent_logs.each do |log|
      domain_name = log.context['domain_name'] || 'Unknown'
      dns_result = log.context['dns_result']
      duration = log.duration_ms
      puts "  #{domain_name}: #{dns_result} (#{duration}ms)"
    end
  end

  desc "Queue all domains for DNS testing"
  task queue_all: :environment do
    count = DomainTestingService.queue_all_domains
    puts "Queued #{count} domains for DNS testing"
  end

  desc "Show domains that need DNS testing"
  task show_pending: :environment do
    total = Domain.count
    untested = Domain.untested.count
    recently_tested = Domain.where('updated_at > ?', 24.hours.ago).where.not(dns: nil).count
    old_tests = Domain.where('updated_at < ?', 24.hours.ago).where.not(dns: nil).count
    
    puts "\nPending DNS Testing Statistics"
    puts "=" * 60
    puts "Total Domains: #{total}"
    puts "Untested Domains: #{untested} (#{(untested * 100.0 / total).round(2)}%)"
    puts "Recently Tested (< 24h): #{recently_tested} (#{(recently_tested * 100.0 / total).round(2)}%)"
    puts "Old Tests (> 24h): #{old_tests} (#{(old_tests * 100.0 / total).round(2)}%)"
    
    # Show some examples of untested domains
    puts "\nSample of Untested Domains:"
    Domain.untested.limit(5).each do |domain|
      puts "  #{domain.domain} (Created: #{domain.created_at.strftime('%Y-%m-%d')})"
    end
  end

  desc "Show DNS testing statistics"
  task stats: :environment do
    puts "\nDNS Testing Statistics"
    puts "=" * 60
    
    # Domain stats
    total = Domain.count
    tested = Domain.where.not(dns: nil).count
    active = Domain.dns_active.count
    inactive = Domain.dns_inactive.count
    
    puts "Domains:"
    puts "  Total: #{total}"
    puts "  Tested: #{tested} (#{(tested * 100.0 / total).round(2)}%)"
    puts "  Active DNS: #{active} (#{(active * 100.0 / tested).round(2)}% of tested)"
    puts "  Inactive DNS: #{inactive}"
    
    # Service Audit Log stats
    sct_logs = ServiceAuditLog.where(service_name: 'domain_testing')
    total_logs = sct_logs.count
    success_logs = sct_logs.successful.count
    failed_logs = sct_logs.failed.count
    
    puts "\nService Audit Logs:"
    puts "  Total Logs: #{total_logs}"
    puts "  Successful: #{success_logs} (#{(success_logs * 100.0 / total_logs).round(2)}%)"
    puts "  Failed: #{failed_logs}"
    
    # Performance stats
    durations = sct_logs.successful.map { |log| log.context['test_duration_ms'] }.compact
    if durations.any?
      puts "\nPerformance:"
      puts "  Average Duration: #{(durations.sum / durations.size).round(2)}ms"
      puts "  Min Duration: #{durations.min}ms"
      puts "  Max Duration: #{durations.max}ms"
    end
    
    # Recent activity
    recent = sct_logs.where('created_at > ?', 24.hours.ago)
    puts "\nRecent Activity (24h):"
    puts "  Tests Run: #{recent.count}"
    puts "  Success Rate: #{(recent.successful.count * 100.0 / recent.count).round(2)}%"
  end
end 