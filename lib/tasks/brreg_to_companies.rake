namespace :brreg do
  desc 'Migrate data from brreg table to companies table using Sidekiq'
  task migrate_to_companies: :environment do
    require 'logger'
    logger = Logger.new(STDOUT)
    batch_size = 1000
    total = Brreg.count
    processed = 0
    last_processed_number = ENV['LAST_NUMBER']&.to_i || 0

    logger.info "Starting migration: #{total} records to process. Batch size: #{batch_size}"

    scope = Brreg.where('organisasjonsnummer > ?', last_processed_number).order('organisasjonsnummer ASC')
    loop do
      batch = scope.limit(batch_size).pluck(:organisasjonsnummer)
      break if batch.empty?

      batch.each do |organisasjonsnummer|
        BrregMigrationWorker.perform_async(organisasjonsnummer)
        processed += 1
        last_processed_number = organisasjonsnummer
      end

      logger.info "Enqueued batch up to Brreg organisasjonsnummer=#{last_processed_number}. Total processed: #{processed}/#{total}"
      # Save progress to a file for resumability
      File.write('tmp/brreg_migration_last_number.txt', last_processed_number)
      
      # Prepare for next batch
      scope = Brreg.where('organisasjonsnummer > ?', last_processed_number).order('organisasjonsnummer ASC')
    end
    logger.info "Migration jobs enqueued. Total records: #{processed}"
  end

  desc 'Resume migration from last processed number'
  task resume_migrate_to_companies: :environment do
    last_number = File.exist?('tmp/brreg_migration_last_number.txt') ? File.read('tmp/brreg_migration_last_number.txt').to_i : 0
    ENV['LAST_NUMBER'] = last_number.to_s
    Rake::Task['brreg:migrate_to_companies'].invoke
  end

  desc 'Backup brreg and companies tables in development'
  task backup_development: :environment do
    backup_file = "#{Rails.root}/backups/brreg_companies_backup_development_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
    system("mkdir -p #{Rails.root}/backups")
    cmd = "pg_dump -h #{ENV['PGHOST']} -U #{ENV['PGUSER']} -d b2b_development -t brreg -t companies > #{backup_file}"
    puts "Running: #{cmd}"
    system(cmd)
    puts "Backup complete: #{backup_file}"
  end

  desc 'Restore brreg and companies tables in development'
  task restore_development: :environment do
    require 'io/console'
    backup_files = Dir.glob("#{Rails.root}/backups/brreg_companies_backup_development_*.sql").sort
    if backup_files.empty?
      puts 'No backup files found.'
      next
    end
    puts 'Available backups:'
    backup_files.each_with_index { |f, i| puts "#{i+1}: #{f}" }
    print 'Select backup to restore (number): '
    idx = STDIN.gets.strip.to_i - 1
    file = backup_files[idx]
    if file.nil?
      puts 'Invalid selection.'
      next
    end
    puts "Restoring from: #{file}"
    system("psql -h #{ENV['PGHOST']} -U #{ENV['PGUSER']} -d b2b_development < #{file}")
    puts 'Restore complete.'
  end

  desc 'Backup brreg and companies tables in production'
  task backup_production: :environment do
    backup_file = "#{Rails.root}/backups/brreg_companies_backup_production_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
    system("mkdir -p #{Rails.root}/backups")
    cmd = "pg_dump -h #{ENV['PGHOST']} -U #{ENV['PGUSER']} -d b2b_production -t brreg -t companies > #{backup_file}"
    puts "Running: #{cmd}"
    system(cmd)
    puts "Backup complete: #{backup_file}"
  end

  desc 'Restore brreg and companies tables in production'
  task restore_production: :environment do
    require 'io/console'
    backup_files = Dir.glob("#{Rails.root}/backups/brreg_companies_backup_production_*.sql").sort
    if backup_files.empty?
      puts 'No backup files found.'
      next
    end
    puts 'Available backups:'
    backup_files.each_with_index { |f, i| puts "#{i+1}: #{f}" }
    print 'Select backup to restore (number): '
    idx = STDIN.gets.strip.to_i - 1
    file = backup_files[idx]
    if file.nil?
      puts 'Invalid selection.'
      next
    end
    puts "Restoring from: #{file}"
    system("psql -h #{ENV['PGHOST']} -U #{ENV['PGUSER']} -d b2b_production < #{file}")
    puts 'Restore complete.'
  end

  desc 'Backup brreg and companies tables in test'
  task backup_test: :environment do
    backup_file = "#{Rails.root}/backups/brreg_companies_backup_test_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
    system("mkdir -p #{Rails.root}/backups")
    cmd = "pg_dump -h #{ENV['PGHOST']} -U #{ENV['PGUSER']} -d b2b_test -t brreg -t companies > #{backup_file}"
    puts "Running: #{cmd}"
    system(cmd)
    puts "Backup complete: #{backup_file}"
  end

  desc 'Restore brreg and companies tables in test'
  task restore_test: :environment do
    require 'io/console'
    backup_files = Dir.glob("#{Rails.root}/backups/brreg_companies_backup_test_*.sql").sort
    if backup_files.empty?
      puts 'No backup files found.'
      next
    end
    puts 'Available backups:'
    backup_files.each_with_index { |f, i| puts "#{i+1}: #{f}" }
    print 'Select backup to restore (number): '
    idx = STDIN.gets.strip.to_i - 1
    file = backup_files[idx]
    if file.nil?
      puts 'Invalid selection.'
      next
    end
    puts "Restoring from: #{file}"
    system("psql -h #{ENV['PGHOST']} -U #{ENV['PGUSER']} -d b2b_test < #{file}")
    puts 'Restore complete.'
  end
end 