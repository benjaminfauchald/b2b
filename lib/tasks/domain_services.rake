namespace :domain do
  desc 'Run DomainTestingService for all applicable domains'
  task test_dns: :environment do
    result = DomainTestingService.new.call
    puts "DomainTestingService completed: #{result.inspect}"
  end

  desc 'Run DomainARecordTestingService for all applicable domains'
  task test_a_record: :environment do
    result = DomainARecordTestingService.new.call
    puts "DomainARecordTestingService completed: #{result.inspect}"
  end

  desc 'Run DomainMxTestingService for domains with both DNS and WWW successful'
  task test_mx: :environment do
    result = DomainMxTestingService.new.call
    puts "DomainMxTestingService completed: #{result.inspect}"
  end
end 