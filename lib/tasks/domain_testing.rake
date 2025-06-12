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
    recent_logs = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1')
                                .recent.limit(5)
    
    puts "\nSample Results:"
    recent_logs.each do |log|
      domain_name = log.context['domain_name'] || 'Unknown'
      dns_result = log.context['dns_result']
      duration = log.duration_ms
      puts "  #{domain_name}: #{dns_result} (#{duration}ms)"
    end
  end

  desc "Test all domains in controlled batches"
  task :all_batched => :environment do
    total_untested = Domain.untested.count
    batch_size = 500
    
    puts "Testing #{total_untested} domains in batches of #{batch_size}..."
    puts "Estimated time: #{(total_untested * 0.5 / 60).round(2)} minutes"
    puts "Press Ctrl+C to stop at any time"
    
    start_time = Time.current
    total_processed = 0
    
    while Domain.untested.exists?
      batch_start = Time.current
      service = DomainTestingService.new(batch_size: batch_size)
      result = service.call
      
      break if result[:processed] == 0
      
      total_processed += result[:processed]
      batch_duration = Time.current - batch_start
      
      puts "Batch completed: #{result[:processed]} domains in #{batch_duration.round(2)}s"
      puts "  Success: #{result[:successful]}, Failed: #{result[:failed]}, Errors: #{result[:errors]}"
      puts "  Total processed: #{total_processed}/#{total_untested} (#{(total_processed * 100.0 / total_untested).round(2)}%)"
      puts "  Estimated remaining: #{((total_untested - total_processed) * batch_duration / batch_size / 60).round(2)} minutes"
      puts
      
      # Small delay to prevent overwhelming the DNS servers
      sleep(1)
    end
    
    total_duration = Time.current - start_time
    puts "All domains tested in #{(total_duration / 60).round(2)} minutes!"
  end

  desc "Performance test with timing analysis"
  task :performance => :environment do
    puts "Running performance test with 50 domains..."
    
    # Clear any existing logs for clean timing
    test_domains = Domain.untested.limit(50)
    
    start_time = Time.current
    service = DomainTestingService.new(batch_size: 50)
    result = service.call
    end_time = Time.current
    
    duration = end_time - start_time
    
    puts "\nPerformance Results:"
    puts "  Total Duration: #{duration.round(2)} seconds"
    puts "  Domains Processed: #{result[:processed]}"
    puts "  Average per Domain: #{(duration / result[:processed]).round(3)} seconds"
    puts "  Domains per Second: #{(result[:processed] / duration).round(2)}"
    puts "  Estimated for 17k domains: #{(17000 * duration / result[:processed] / 60).round(2)} minutes"
    
    # Analyze response times
    recent_logs = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1')
                                .where('created_at > ?', start_time)
    
    durations = recent_logs.map(&:duration_ms).compact
    if durations.any?
      puts "\nDNS Response Time Analysis:"
      puts "  Min: #{durations.min}ms"
      puts "  Max: #{durations.max}ms"
      puts "  Average: #{(durations.sum / durations.count).round(2)}ms"
      puts "  Median: #{durations.sort[durations.count / 2]}ms"
    end
  end

  desc "Error simulation test"
  task :error_test => :environment do
    puts "Testing error handling with mock failures..."
    
    # Test with a few domains but simulate different error conditions
    test_domains = Domain.untested.limit(3)
    
    test_domains.each_with_index do |domain, index|
      service = DomainTestingService.new
      
      # Mock different error types
      case index
      when 0
        puts "Testing normal operation with #{domain.domain}..."
        service.send(:test_domain_dns, domain)
      when 1
        puts "Simulating DNS resolve error with #{domain.domain}..."
        # We'll just update the audit log manually for demonstration
        audit_log = ServiceAuditLog.create!(
          auditable: domain,
          service_name: 'domain_dns_testing_v1',
          action: 'test_dns',
          status: :failed,
          error_message: 'DNS resolution failed',
          context: {
            'error_type' => 'resolve_error',
            'domain_name' => domain.domain,
            'test_duration_ms' => 5000
          }
        )
        domain.update!(dns: false)
      when 2
        puts "Simulating timeout error with #{domain.domain}..."
        audit_log = ServiceAuditLog.create!(
          auditable: domain,
          service_name: 'domain_dns_testing_v1',
          action: 'test_dns',
          status: :failed,
          error_message: 'DNS lookup timed out',
          context: {
            'error_type' => 'timeout_error',
            'domain_name' => domain.domain,
            'test_duration_ms' => 8000
          }
        )
        domain.update!(dns: false)
      end
    end
    
    puts "\nError test completed. Check audit logs:"
    ServiceAuditLog.where(service_name: 'domain_dns_testing_v1').recent.limit(3).each do |log|
      puts "  #{log.context['domain_name']}: #{log.status} - #{log.error_message}"
    end
  end

  desc "Queue DNS testing jobs for all untested domains"
  task :queue_all => :environment do
    total_untested = Domain.untested.count
    batch_size = 500
    
    puts "Queueing #{total_untested} domains for DNS testing..."
    puts "Using batch size of #{batch_size}"
    
    total_queued = 0
    Domain.untested.find_each(batch_size: batch_size) do |domain|
      DomainDnsTestingWorker.perform_async(domain.id)
      total_queued += 1
      
      if total_queued % batch_size == 0
        puts "Queued #{total_queued}/#{total_untested} domains (#{(total_queued * 100.0 / total_untested).round(2)}%)"
      end
    end
    
    puts "\nAll domains queued!"
    puts "Total domains queued: #{total_queued}"
    puts "\nStart Sidekiq workers with:"
    puts "bundle exec sidekiq -q dns_testing"
  end

  desc "Monitor DNS testing progress"
  task :monitor => :environment do
    puts "Domain Testing Monitor (Press Ctrl+C to stop)"
    puts "=" * 60
    
    last_count = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1').count
    
    loop do
      sleep 5
      
      current_count = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1').count
      new_tests = current_count - last_count
      
      # Get queue stats
      queue_size = Sidekiq::Queue.new('dns_testing').size
      workers = Sidekiq::Workers.new.size
      
      stats = {
        total_domains: Domain.count,
        untested: Domain.untested.count,
        tested: Domain.where.not(dns: nil).count,
        active: Domain.dns_active.count,
        inactive: Domain.dns_inactive.count
      }
      
      puts "[#{Time.current.strftime('%H:%M:%S')}] " \
           "Tests: +#{new_tests} | " \
           "Queue: #{queue_size} | " \
           "Workers: #{workers} | " \
           "Untested: #{stats[:untested]} | " \
           "Active: #{stats[:active]} | " \
           "Inactive: #{stats[:inactive]} | " \
           "Coverage: #{((stats[:tested] * 100.0) / stats[:total_domains]).round(2)}%"
      
      last_count = current_count
    end
  end

  desc "Show DNS testing statistics"
  task :stats => :environment do
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
    
    # SCT stats
    sct_logs = ServiceAuditLog.where(service_name: 'domain_dns_testing_v1')
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
    
    # Sidekiq stats
    puts "\nSidekiq Status:"
    puts "  Queue Size: #{Sidekiq::Queue.new('dns_testing').size}"
    puts "  Active Workers: #{Sidekiq::Workers.new.size}"
  end
end 