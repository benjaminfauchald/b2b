namespace :domain_a_record_testing do
  desc 'Test A records for a sample of domains'
  task sample: :environment do
    domains = Domain.dns_active.where(www: nil).order('RANDOM()').limit(10)
    puts "Testing A records for #{domains.count} domains..."
    
    domains.each do |domain|
      service = DomainARecordTestingService.new(domain: domain)
      result = service.call
      
      puts "Domain: #{domain.domain}"
      puts "Status: #{result ? 'Success' : 'Failed'}"
      puts "WWW Status: #{domain.reload.www ? 'Active' : 'Inactive'}"
      puts "---"
    end
  end

  desc 'Test A records for all domains in batches'
  task queue_all: :environment do
    batch_size = ENV['BATCH_SIZE']&.to_i || 100
    puts "Queueing all domains for A record testing in batches of #{batch_size}..."
    
    count = DomainARecordTestingService.queue_all_domains
    puts "Queued #{count} domains for A record testing"
  end

  desc 'Show domains that need A record testing'
  task show_pending: :environment do
    domains = Domain.dns_active.where(www: nil)
    puts "Found #{domains.count} domains needing A record testing:"
    domains.each do |domain|
      puts "#{domain.domain} (Last updated: #{domain.updated_at})"
    end
  end

  desc 'Show A record testing statistics'
  task stats: :environment do
    total = Domain.count
    tested = Domain.where.not(www: nil).count
    untested = Domain.where(www: nil).count
    outdated = Domain.where('updated_at < ?', 1.day.ago).count

    puts "A Record Testing Statistics:"
    puts "Total domains: #{total}"
    puts "Tested domains: #{tested} (#{(tested.to_f / total * 100).round(2)}%)"
    puts "Untested domains: #{untested} (#{(untested.to_f / total * 100).round(2)}%)"
    puts "Outdated tests: #{outdated} (#{(outdated.to_f / total * 100).round(2)}%)"
  end
end 