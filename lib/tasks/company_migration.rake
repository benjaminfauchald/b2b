namespace :companies do
  desc "Migrate Company data from app.connectica.no to localhost"
  task migrate_from_production: :environment do
    require 'pg'
    
    puts "Starting Company migration from app.connectica.no to localhost..."

    # Progress tracking
    progress_file = Rails.root.join("tmp", "company_migration_progress.txt")
    start_from = 0

    # Resume from last processed record if progress file exists
    if File.exist?(progress_file)
      start_from = File.read(progress_file).strip.to_i
      puts "Resuming from company ID: #{start_from}"
    end

    # Database connection settings for remote production database
    remote_db_config = {
      host: "app.connectica.no",
      port: 5432,
      dbname: "b2b_production",
      user: "benjamin",
      password: "Charcoal2020!"
    }

    batch_size = ENV["BATCH_SIZE"]&.to_i || 1000
    total_migrated = 0
    total_skipped = 0
    total_errors = 0

    begin
      # Connect to remote database
      remote_conn = PG.connect(remote_db_config)
      puts "Connected to remote production database at app.connectica.no"

      # Get total count for progress tracking
      total_count_result = remote_conn.exec("SELECT COUNT(*) FROM companies WHERE id > #{start_from}")
      total_count = total_count_result[0]["count"].to_i
      puts "Total company records to process: #{total_count}"

      # Get local company count before migration
      local_count_before = Company.count
      puts "Local companies before migration: #{local_count_before}"
      puts ""

      # Process in batches
      loop do
        puts "\nProcessing batch starting from company ID: #{start_from}"

        # Fetch batch from remote database
        query = <<-SQL
          SELECT * FROM companies 
          WHERE id > #{start_from}
          ORDER BY id 
          LIMIT #{batch_size}
        SQL

        result = remote_conn.exec(query)
        break if result.ntuples == 0

        # Process each record in transaction
        ActiveRecord::Base.transaction do
          result.each do |remote_record|
            begin
              company_id = remote_record["id"]
              registration_number = remote_record["registration_number"]

              # Check if company already exists by registration number
              if registration_number.present?
                existing_company = Company.find_by(registration_number: registration_number)
                if existing_company
                  Rails.logger.debug "Skipping existing company with registration_number: #{registration_number}"
                  total_skipped += 1
                  next
                end
              end

              # Create new company with all attributes from remote
              company_attrs = {}
              
              # Copy all fields that exist in both remote and local Company model
              remote_record.each do |key, value|
                if Company.column_names.include?(key) && key != "id"
                  # Handle special cases for data types
                  case key
                  when "created_at", "updated_at"
                    company_attrs[key] = Time.parse(value) if value.present?
                  when "registration_date", "bankruptcy_date", "liquidation_date", "deregistration_date", 
                       "vat_registration_date", "employee_registration_date_registry", "employee_registration_date_nav"
                    begin
                      company_attrs[key] = Date.parse(value) if value.present?
                    rescue Date::Error
                      Rails.logger.warn "Invalid date format for #{key}: #{value}"
                    end
                  when "bankruptcy", "under_liquidation", "vat_registered", "has_registered_employees"
                    company_attrs[key] = value == "t" || value == true
                  when "employee_count", "brreg_id"
                    company_attrs[key] = value.to_i if value.present?
                  else
                    company_attrs[key] = value
                  end
                end
              end

              # Create company record
              company = Company.create!(company_attrs)
              Rails.logger.debug "✓ Created company: #{company.company_name} (#{registration_number})"
              total_migrated += 1

              # Update progress with the last processed ID
              File.write(progress_file, company_id)

            rescue => e
              Rails.logger.error "Error processing company ID #{remote_record['id']}: #{e.message}"
              Rails.logger.error e.backtrace.first(3).join("\n") if ENV["DEBUG"]
              total_errors += 1
              next
            end
          end
        end

        # Update start_from for next batch
        last_record = result[result.ntuples - 1]
        start_from = last_record["id"].to_i

        puts "Batch complete. Migrated: #{total_migrated}, Skipped: #{total_skipped}, Errors: #{total_errors}"

        # Small delay to prevent overwhelming the database
        sleep(0.1)
      end

    rescue => e
      Rails.logger.error "Migration failed: #{e.message}"
      puts "Migration failed: #{e.message}"
      raise
    ensure
      remote_conn&.close
      puts "Remote database connection closed"
    end

    local_count_after = Company.count
    
    puts "\n" + "="*50
    puts "Company migration completed!"
    puts "Total migrated: #{total_migrated}"
    puts "Total skipped: #{total_skipped}"
    puts "Total errors: #{total_errors}"
    puts "Local companies before: #{local_count_before}"
    puts "Local companies after: #{local_count_after}"
    puts "Net increase: #{local_count_after - local_count_before}"
    puts "="*50

    # Clean up progress file on successful completion
    File.delete(progress_file) if File.exist?(progress_file) && total_errors == 0
  end
end