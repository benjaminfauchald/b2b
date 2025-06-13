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

  desc 'Run DomainSuccessfulTestService for domains with both DNS and WWW successful'
  task test_successful: :environment do
    result = DomainSuccessfulTestService.new.call
    puts "DomainSuccessfulTestService completed: #{result.inspect}"
  end
end 