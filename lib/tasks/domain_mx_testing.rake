namespace :domain_mx_testing do
  desc "Queue a single random pending domain for MX testing via worker"
  task sample: :environment do
    domain = Domain.where(mx: nil).order("RANDOM()").first
    if domain
      DomainMxTestingWorker.perform_async(domain.id)
      puts "Queued domain ##{domain.id} (#{domain.domain}) for MX testing."
    else
      puts "No pending domains found."
    end
  end

  desc "Queue all pending domains for MX testing via worker"
  task queue_all: :environment do
    count = DomainMxTestingService.queue_all_domains
    puts "Queued #{count} domains for MX testing."
  end

  desc "Show domains pending MX testing and their stats"
  task show_pending: :environment do
    domains = Domain.where(mx: nil)
    total = Domain.count
    pending = domains.count
    tested = Domain.where.not(mx: nil).count
    failed = Domain.where.not(mx_error: [ nil, "" ]).count

    puts "\nMX Testing Statistics:"
    puts "Total domains: #{total}"
    puts "Pending MX test: #{pending}"
    puts "Tested: #{tested}"
    puts "Failed: #{failed}"
    puts "Pending percentage: #{(pending.to_f / total * 100).round(2)}%"

    if domains.any?
      puts "\nPending domains for MX testing:"
      domains.each { |d| puts "##{d.id}: #{d.domain}" }
    else
      puts "\nNo pending domains for MX testing."
    end
  end

  desc "Show MX testing stats"
  task stats: :environment do
    total = Domain.count
    pending = Domain.where(mx: nil).count
    tested = Domain.where.not(mx: nil).count
    failed = Domain.where.not(mx_error: [ nil, "" ]).count
    puts "Total domains: #{total}"
    puts "Pending MX test: #{pending}"
    puts "Tested: #{tested}"
    puts "Failed: #{failed}"
  end
end
