# Helper methods for Puppeteer tests

def get_sidekiq_stats
  require 'sidekiq/api'
  stats = {}
  stats[:dns_queue] = Sidekiq::Queue.new('domain_dns_testing').size
  stats[:mx_queue] = Sidekiq::Queue.new('domain_mx_testing').size
  stats[:default_queue] = Sidekiq::Queue.new('default').size

  # Count specific workers in default queue
  default_queue = Sidekiq::Queue.new('default')
  stats[:a_record_workers] = default_queue.count { |job| job.klass == 'DomainARecordTestingWorker' }
  stats[:web_content_workers] = default_queue.count { |job| job.klass == 'DomainWebContentExtractionWorker' }

  stats[:total_enqueued] = Sidekiq::Stats.new.enqueued
  stats[:total_processed] = Sidekiq::Stats.new.processed
  stats
rescue => e
  # Return default stats if Sidekiq is not available
  { dns_queue: 0, mx_queue: 0, default_queue: 0, a_record_workers: 0, 
    web_content_workers: 0, total_enqueued: 0, total_processed: 0, 
    error: e.message }
end

def get_recent_audit_logs(limit = 10)
  logs = ServiceAuditLog.order(created_at: :desc).limit(limit)
  logs.map do |log|
    {
      id: log.id,
      service_name: log.service_name,
      operation_type: log.operation_type,
      status: log.status,
      auditable_type: log.auditable_type,
      auditable_id: log.auditable_id,
      created_at: log.created_at.iso8601,
      execution_time_ms: log.execution_time_ms
    }
  end
end

def create_test_domains(count)
  domains = []
  count.times do |i|
    domain = Domain.create!(
      domain: "test-domain-#{Time.current.to_i}-#{i}.com",
      dns: nil,
      mx: nil,
      www: nil
    )
    domains << domain.id
  end
  domains
end

def get_domains_needing_service
  {
    dns_needed: Domain.needing_service('domain_testing').count,
    mx_needed: Domain.needing_service('domain_mx_testing').count,
    a_record_needed: Domain.needing_service('domain_a_record_testing').count,
    web_content_needed: Domain.needing_service('domain_web_content_extraction').count
  }
end

def get_processed_domain_stats
  test_domains = Domain.where("domain LIKE ?", "test-domain-%")
  {
    total: test_domains.count,
    dns_tested: test_domains.where.not(dns: nil).count,
    dns_active: test_domains.where(dns: true).count,
    mx_tested: test_domains.where.not(mx: nil).count,
    www_tested: test_domains.where.not(www: nil).count
  }
end

def cleanup_test_domains
  deleted = Domain.where("domain LIKE ?", "test-domain-%").destroy_all
  { deleted_count: deleted.count }
end

# Execute command if provided
if ARGV[0]
  # Disable Rails logger output to stdout
  Rails.logger = Logger.new('/dev/null')
  ActiveRecord::Base.logger = nil
  
  result = case ARGV[0]
  when 'sidekiq_stats'
    get_sidekiq_stats
  when 'audit_logs'
    limit = ARGV[1]&.to_i || 10
    get_recent_audit_logs(limit)
  when 'create_domains'
    count = ARGV[1]&.to_i || 50
    create_test_domains(count)
  when 'domains_needing'
    get_domains_needing_service
  when 'processed_stats'
    get_processed_domain_stats
  when 'cleanup'
    cleanup_test_domains
  end
  
  # Write to file to avoid stdout pollution
  output_file = Rails.root.join("tmp", "rails_helper_output_#{Process.pid}.json").to_s
  File.write(output_file, result.to_json)
  puts output_file
end