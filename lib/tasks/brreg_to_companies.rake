namespace :brreg do
  desc 'Migrate data from brreg table to companies table'
  task migrate_to_companies: :environment do
    require 'logger'
    logger = Logger.new(STDOUT)
    batch_size = 1000
    total = Brreg.count
    processed = 0
    errors = 0
    last_processed_id = ENV['LAST_ID']&.to_i || 0

    logger.info "Starting migration: #{total} records to process. Batch size: #{batch_size}"

    Brreg.where('id > ?', last_processed_id).find_in_batches(batch_size: batch_size) do |batch|
      ActiveRecord::Base.transaction do
        batch.each do |br|
          begin
            company_attrs = {
              source_country: 'NO',
              source_registry: 'brreg',
              source_id: br.organisasjonsnummer,
              registration_number: br.organisasjonsnummer,
              company_name: br.navn,
              organization_form_code: br.organisasjonsform_kode,
              organization_form_description: br.organisasjonsform_beskrivelse,
              primary_industry_code: br.naeringskode1_kode,
              primary_industry_description: br.naeringskode1_beskrivelse,
              secondary_industry_code: br.naeringskode2_kode,
              secondary_industry_description: br.naeringskode2_beskrivelse,
              tertiary_industry_code: br.naeringskode3_kode,
              tertiary_industry_description: br.naeringskode3_beskrivelse,
              business_description: br.aktivitet,
              employee_count: br.antallansatte,
              website: br.hjemmeside,
              email: br.epost,
              phone: br.telefon,
              mobile: br.mobiltelefon,
              business_address: br.forretningsadresse,
              business_city: br.forretningsadresse_poststed,
              business_postal_code: br.forretningsadresse_postnummer,
              business_municipality: br.forretningsadresse_kommune,
              business_country: br.forretningsadresse_land,
              operating_revenue: br.driftsinntekter,
              operating_costs: br.driftskostnad,
              ordinary_result: br.ordinaertResultat,
              annual_result: br.aarsresultat,
              vat_registered: br.mvaregistrert,
              vat_registration_date: br.mvaregistrertdato,
              voluntary_vat_registered: br.frivilligmvaregistrert,
              voluntary_vat_registration_date: br.frivilligmvaregistrertdato,
              registration_date: br.stiftelsesdato,
              bankruptcy: br.konkurs,
              bankruptcy_date: br.konkursdato,
              under_liquidation: br.underavvikling,
              liquidation_date: br.avviklingsdato,
              linkedin_url: br.linked_in,
              linkedin_ai_url: br.linked_in_ai,
              linkedin_alternatives: br.linked_in_alternatives,
              linkedin_processed: br.linked_in_processed,
              linkedin_last_processed_at: br.linked_in_last_processed_at,
              http_error: br.http_error,
              http_error_message: br.http_error_message,
              source_raw_data: br.brreg_result_raw,
              description: br.description
            }
            # Upsert by registration_number
            company = Company.find_or_initialize_by(registration_number: br.organisasjonsnummer)
            company.assign_attributes(company_attrs)
            company.save!
            processed += 1
            last_processed_id = br.id
          rescue => e
            logger.error "Error processing Brreg id=#{br.id}: #{e.message}"
            errors += 1
          end
        end
        logger.info "Processed batch up to Brreg id=#{last_processed_id}. Total processed: #{processed}/#{total}, Errors: #{errors}"
        # Save progress to a file for resumability
        File.write('tmp/brreg_migration_last_id.txt', last_processed_id)
      end
    end
    logger.info "Migration complete. Total processed: #{processed}, Errors: #{errors}"
  end

  desc 'Resume migration from last processed id'
  task resume_migrate_to_companies: :environment do
    last_id = File.exist?('tmp/brreg_migration_last_id.txt') ? File.read('tmp/brreg_migration_last_id.txt').to_i : 0
    ENV['LAST_ID'] = last_id.to_s
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