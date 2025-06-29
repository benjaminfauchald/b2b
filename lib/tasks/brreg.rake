namespace :brreg do
  desc "Process a sample of brreg records"
  task sample: :environment do
    logger = Logger.new(STDOUT)
    count = ENV["COUNT"]&.to_i || 5

    logger.info ""
    logger.info "Brreg Sample Processing"
    logger.info "=" * 60
    logger.info "Processing #{count} random records...\n"

    Brreg.order("RANDOM()").limit(count).each do |record|
      logger.info "Organization: #{record.navn} (##{record.organisasjonsnummer})"
      logger.info "Type: #{record.organisasjonsform_beskrivelse || 'N/A'}"
      logger.info "Industry: #{record.naeringskode1_beskrivelse || 'N/A'}"
      logger.info "Employees: #{record.antallansatte || 'N/A'}"
      logger.info "Website: #{record.hjemmeside || 'N/A'}"
      logger.info "Address: #{[ record.forretningsadresse_adresse, record.forretningsadresse_postnummer, record.forretningsadresse_poststed ].compact.join(', ')}"

      # Check if this record has been processed recently
      last_processed = ServiceAuditLog
        .where(service_name: "brreg")
        .where(auditable_type: "Brreg")
        .where("auditable_id::text = ?", record.organisasjonsnummer.to_s)
        .order(created_at: :desc)
        .first

      if last_processed
        logger.info "Last Processed: #{last_processed.created_at} (#{last_processed.status})"
        logger.info "Duration: #{last_processed.duration_ms}ms" if last_processed.duration_ms
      else
        logger.info "Status: Not yet processed"
      end

      logger.info ""
    end

    logger.info "Sample processing complete"
    logger.info "=" * 60
  end

  desc "Queue all brreg records for processing"
  task queue_all: :environment do
    batch_size = ENV["BATCH_SIZE"]&.to_i || 1000
    total = Brreg.count
    processed = 0
    last_processed_number = ENV["LAST_NUMBER"]&.to_i || 0

    puts "\nBrreg Queue All Processing"
    puts "============================================================"
    puts "Total records to process: #{total}"
    puts "Batch size: #{batch_size}"
    puts "Starting from record number: #{last_processed_number}"

    scope = Brreg.where("organisasjonsnummer > ?", last_processed_number).order("organisasjonsnummer ASC")

    loop do
      batch = scope.limit(batch_size)
      break if batch.empty?

      BrregKafkaProducer.produce_batch(batch)
      processed += batch.size
      last_processed_number = batch.last.organisasjonsnummer

      puts "Processed batch up to #{last_processed_number} (#{processed}/#{total})"
      File.write("tmp/brreg_last_number.txt", last_processed_number)

      scope = Brreg.where("organisasjonsnummer > ?", last_processed_number).order("organisasjonsnummer ASC")
    end

    puts "\nProcessing complete!"
    puts "Total records queued: #{processed}"
  end

  desc "Show pending brreg records"
  task show_pending: :environment do
    total = Brreg.count
    processed = Company.where.not(brreg_id: nil).count
    untested = total - processed
    recent = Company.where("created_at > ?", 24.hours.ago).where.not(brreg_id: nil).count
    old = processed - recent

    puts "\nPending Brreg Processing Statistics"
    puts "============================================================"
    puts "Total Records: #{total}"
    puts "Untested Records: #{untested} (#{(untested.to_f/total*100).round(2)}%)"
    puts "Recently Processed (< 24h): #{recent} (#{(recent.to_f/total*100).round(2)}%)"
    puts "Old Processing (> 24h): #{old} (#{(old.to_f/total*100).round(2)}%)"

    puts "\nSample of Untested Records:"
    Brreg.left_outer_joins(:company)
         .where(companies: { id: nil })
         .order("RANDOM()")
         .limit(5)
         .each do |record|
      puts "  #{record.organisasjonsnummer} - #{record.navn} (Created: #{record.created_at.strftime('%Y-%m-%d')})"
    end
  end

  desc "Show brreg processing statistics"
  task stats: :environment do
    total = Brreg.count
    processed = Company.where.not(brreg_id: nil).count
    successful = Company.where.not(brreg_id: nil).where.not(status: "error").count
    failed = Company.where.not(brreg_id: nil).where(status: "error").count

    recent_logs = ServiceAuditLog.where(service_name: "brreg")
                                .where("created_at > ?", 24.hours.ago)
    recent_success = recent_logs.where(status: :success).count
    recent_total = recent_logs.count
    success_rate = recent_total > 0 ? (recent_success.to_f / recent_total * 100).round(2) : 0

    avg_duration = recent_logs.average(:duration_ms)&.round || 0
    min_duration = recent_logs.minimum(:duration_ms) || 0
    max_duration = recent_logs.maximum(:duration_ms) || 0

    puts "\nBrreg Processing Statistics"
    puts "============================================================"
    puts "Records:"
    puts "  Total: #{total}"
    puts "  Processed: #{processed} (#{(processed.to_f/total*100).round(2)}%)"
    puts "  Successful: #{successful} (#{(successful.to_f/processed*100).round(2)}% of processed)"
    puts "  Failed: #{failed}"

    puts "\nService Audit Logs:"
    puts "  Total Logs: #{recent_total}"
    puts "  Successful: #{recent_success} (#{success_rate}%)"
    puts "  Failed: #{recent_total - recent_success}"

    puts "\nPerformance:"
    puts "  Average Duration: #{avg_duration}ms"
    puts "  Min Duration: #{min_duration}ms"
    puts "  Max Duration: #{max_duration}ms"

    puts "\nRecent Activity (24h):"
    puts "  Records Processed: #{recent_total}"
    puts "  Success Rate: #{success_rate}%"
  end

  desc "Migrate data from Brreg to Company model"
  task migrate_to_companies: :environment do
    logger = Logger.new(STDOUT)
    batch_size = ENV["BATCH_SIZE"]&.to_i || 1000
    total = Brreg.count
    processed = 0
    success_count = 0
    skipped_count = 0
    error_count = 0
    batch_index = 0

    logger.info "\nStarting Brreg to Company migration"
    logger.info "Total Brreg records to process: #{total}"
    logger.info "Batch size: #{batch_size}"
    logger.info "Current Company count: #{Company.count}"
    logger.info "=" * 60

    # Process Brreg records in batches
    Brreg.find_in_batches(batch_size: batch_size) do |batch|
      batch_index += 1
      logger.info "Processing batch ##{batch_index} (records #{processed + 1} - #{processed + batch.size})"

      ActiveRecord::Base.transaction do
        batch.each do |brreg_record|
          begin
            # Find or create company by registration number (organisasjonsnummer)
            company = Company.find_or_initialize_by(registration_number: brreg_record.organisasjonsnummer)

            # Skip if the company already exists and hasn't changed
            if company.persisted? && !company_changed?(company, brreg_record)
              logger.debug "Skipping company #{brreg_record.organisasjonsnummer} - no changes detected"
              skipped_count += 1
              next
            end

            # Update company with Brreg data
            update_company_attributes(company, brreg_record)

            if company.save!
              success_count += 1
              action = company.previously_new_record? ? "created" : "updated"
              logger.debug "Successfully #{action} company: #{brreg_record.organisasjonsnummer}"
            end

          rescue ActiveRecord::RecordNotUnique => e
            logger.error "Skipping duplicate registration number: #{brreg_record.organisasjonsnummer} - #{e.message}"
            skipped_count += 1
          rescue => e
            error_count += 1
            logger.error "Error processing Brreg record #{brreg_record.organisasjonsnummer}: #{e.message}"
            logger.error e.backtrace.join("\n") if ENV["DEBUG"]
          end

          processed += 1
        end
      end

      progress_percent = ((processed.to_f / total) * 100).round(1)
      logger.info "Processed #{processed}/#{total} records (#{progress_percent}%)"
      logger.info "Success: #{success_count}, Skipped: #{skipped_count}, Errors: #{error_count}"
      logger.info ""
    end

    final_company_count = Company.count
    logger.info "\nMigration completed!"
    logger.info "Total Brreg records processed: #{processed}"
    logger.info "Successfully migrated: #{success_count}"
    logger.info "Skipped (no changes/duplicates): #{skipped_count}"
    logger.info "Errors: #{error_count}"
    logger.info "Company count before: #{final_company_count - success_count}"
    logger.info "Company count after: #{final_company_count}"
    logger.info "=" * 60
  end

  desc "Migrate domain data from remote database"
  task migrate_domains_from_remote: :environment do
    logger = Logger.new(STDOUT)
    batch_size = ENV["BATCH_SIZE"]&.to_i || 1000
    start_from_id = ENV["START_FROM_ID"]&.to_i || 0

    # Hard-coded remote database configuration (b2b.connectica.no)
    remote_config = {
      adapter: "postgresql",
      encoding: "unicode",
      pool: 5,
      database: "b2b_development",
      host: "b2b.connectica.no",
      port: 5432,
      username: "postgres",
      password: "Charcoal2020!"
    }

    # Hard-coded local/production database configuration (app.connectica.no)
    local_config = {
      adapter: "postgresql",
      encoding: "unicode",
      pool: 5,
      database: "b2b_production",
      host: "app.connectica.no",
      port: 5432,
      username: "benjamin",
      password: "Charcoal2020!"
    }

    logger.info "\nStarting remote Domain data migration"
    logger.info "Remote source: #{remote_config[:host]} (#{remote_config[:database]})"
    logger.info "Local destination: #{local_config[:host]} (#{local_config[:database]})"
    logger.info "Batch size: #{batch_size}"
    logger.info "Starting from ID: #{start_from_id}"
    logger.info "=" * 80

    begin
      # Establish connection to remote database
      ActiveRecord::Base.establish_connection(remote_config)
      remote_connection = ActiveRecord::Base.connection
      logger.info "✓ Connected to remote database successfully"

      # Get total count from remote database
      total_remote = remote_connection.select_value("SELECT COUNT(*) FROM domains WHERE id > #{start_from_id}")
      local_count_before = Domain.count

      logger.info "Remote records to process: #{total_remote}"
      logger.info "Local records before migration: #{local_count_before}"

      # Check if migration might already be complete
      if total_remote == 0
        logger.info "No records to migrate from remote database."
        logger.info "Migration completed successfully!"
        return
      end

      logger.info ""

      processed = 0
      success_count = 0
      skipped_count = 0
      error_count = 0
      last_processed_id = start_from_id

      # Process in batches
      loop do
        # Fetch batch from remote database (using id for ordering)
        batch_sql = <<-SQL
          SELECT * FROM domains#{' '}
          WHERE id > #{last_processed_id}#{' '}
          ORDER BY id ASC#{' '}
          LIMIT #{batch_size}
        SQL

        batch_results = remote_connection.select_all(batch_sql)
        break if batch_results.empty?

        logger.info "Processing batch starting from ID #{last_processed_id + 1}..."
        batch_start_time = Time.current

        # Temporarily reconnect to local database for processing
        ActiveRecord::Base.establish_connection(local_config)

        # Process each record in the batch
        ActiveRecord::Base.transaction do
          batch_results.each do |remote_record|
            begin
              # Always update the last processed ID, even for skipped records
              current_id = remote_record["id"].to_i

              # Check if record already exists (skip duplicates by domain name)
              existing = Domain.find_by(domain: remote_record["domain"])

              if existing
                logger.debug "Skipping existing domain: #{remote_record['domain']}"
                skipped_count += 1
                processed += 1
                last_processed_id = [ last_processed_id, current_id ].max
                next
              end

              # Create new local record
              new_record = Domain.new

              # Map all fields from remote record
              remote_record.each do |key, value|
                if new_record.respond_to?("#{key}=")
                  # Handle datetime fields
                  if %w[created_at updated_at].include?(key) && value.is_a?(String)
                    begin
                      value = DateTime.parse(value) if value.present?
                    rescue DateTime::Error
                      logger.warn "Invalid datetime in #{key} for domain #{remote_record['domain']}"
                      value = nil
                    end
                  end

                  new_record.send("#{key}=", value)
                else
                  logger.debug "Skipping field #{key} - not found in local model"
                end
              end

              # Save the record
              if new_record.save!
                success_count += 1
                logger.debug "✓ Created domain: #{remote_record['domain']}"
              end

            rescue ActiveRecord::RecordNotUnique => e
              logger.warn "Skipping duplicate domain: #{remote_record['domain']}"
              skipped_count += 1
            rescue => e
              error_count += 1
              logger.error "✗ Error processing domain #{remote_record['domain']}: #{e.message}"
              logger.error e.backtrace.first(3).join("\n") if ENV["DEBUG"]
            end

            processed += 1
            current_id = remote_record["id"].to_i
            last_processed_id = [ last_processed_id, current_id ].max
          end
        end

        # Reconnect to remote database for next batch
        ActiveRecord::Base.establish_connection(remote_config)
        remote_connection = ActiveRecord::Base.connection

        batch_duration = Time.current - batch_start_time
        progress_percent = ((processed.to_f / total_remote) * 100).round(2)

        logger.info "Batch completed in #{batch_duration.round(2)}s"
        logger.info "Progress: #{processed}/#{total_remote} (#{progress_percent}%)"
        logger.info "Success: #{success_count}, Skipped: #{skipped_count}, Errors: #{error_count}"
        logger.info "Last processed ID: #{last_processed_id}"

        # Save progress to file for resumability
        File.write("tmp/domain_migration_progress.txt", last_processed_id.to_s)
        logger.info ""

        # Small delay to prevent overwhelming the databases
        sleep(0.1)
      end

    rescue => e
     logger.error "Fatal error during migration: #{e.message}"
     logger.error e.backtrace.join("\n") if ENV["DEBUG"]
     raise
    ensure
      # Always restore the local connection
      begin
        ActiveRecord::Base.establish_connection(local_config)
      rescue => e
        logger.warn "Warning: Could not restore local database connection: #{e.message}"
      end
    end

    local_count_after = Domain.count

    logger.info "\n" + "=" * 80
    logger.info "Domain migration completed!"
    logger.info "Total processed: #{processed}"
    logger.info "Successfully migrated: #{success_count}"
    logger.info "Skipped (duplicates): #{skipped_count}"
    logger.info "Errors: #{error_count}"
    logger.info "Local count before: #{local_count_before}"
    logger.info "Local count after: #{local_count_after}"
    logger.info "Net increase: #{local_count_after - local_count_before}"
    logger.info "=" * 80

    # Clean up progress file on successful completion
    File.delete("tmp/domain_migration_progress.txt") if File.exist?("tmp/domain_migration_progress.txt") && error_count == 0
  end

  desc "Migrate Company data with financial data from app.connectica.no to localhost"
  task migrate_companies_from_production: :environment do
    puts "Starting Company migration with financial data from app.connectica.no to localhost..."

    # Progress tracking
    progress_file = Rails.root.join("tmp", "company_migration_progress.txt")
    start_from = "0"

    # Resume from last processed record if progress file exists
    if File.exist?(progress_file)
      start_from = File.read(progress_file).strip
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
    total_updated = 0
    total_skipped = 0
    total_errors = 0
    financial_data_copied = 0

    begin
      # Connect to remote database
      remote_conn = PG.connect(remote_db_config)
      Rails.logger.info "Connected to remote production database"

      # Get total count for progress tracking - now from companies table
      total_count_result = remote_conn.exec("SELECT COUNT(*) FROM companies WHERE registration_number > '#{start_from}'")
      total_count = total_count_result[0]["count"].to_i
      puts "Total companies to process: #{total_count}"

      # Process in batches
      loop do
        puts "\nProcessing batch starting from registration_number: #{start_from}"

        # Fetch batch from remote companies table (not brreg)
        query = <<-SQL
          SELECT * FROM companies#{' '}
          WHERE registration_number > '#{start_from}'
          ORDER BY registration_number#{' '}
          LIMIT #{batch_size}
        SQL

        result = remote_conn.exec(query)
        break if result.ntuples == 0

        # Process each record in transaction
        ActiveRecord::Base.transaction do
          result.each do |remote_record|
            begin
              registration_number = remote_record["registration_number"]

              # Check if company already exists
              existing_company = Company.find_by(registration_number: registration_number)

              # Build company attributes including financial data
              company_attrs = build_company_attributes(remote_record)

              if existing_company
                # Update existing company with all data including financial
                existing_company.update!(company_attrs)
                Rails.logger.debug "✓ Updated company: #{registration_number}"
                total_updated += 1

                # Check if financial data was updated
                if has_financial_data?(remote_record)
                  financial_data_copied += 1
                end
              else
                # Create new company record
                company = Company.create!(company_attrs)
                Rails.logger.debug "✓ Created company: #{registration_number}"
                total_migrated += 1

                # Check if financial data was included
                if has_financial_data?(remote_record)
                  financial_data_copied += 1
                end
              end

              # Update progress
              File.write(progress_file, registration_number)

            rescue => e
              Rails.logger.error "Error processing company #{registration_number}: #{e.message}"
              Rails.logger.error "Error details: #{e.backtrace.first(3).join("\n")}" if ENV["DEBUG"]
              total_errors += 1
              next
            end
          end
        end

        # Update start_from for next batch
        last_record = result[result.ntuples - 1]
        start_from = last_record["registration_number"]

        puts "Batch complete. Migrated: #{total_migrated}, Updated: #{total_updated}, Financial data: #{financial_data_copied}, Errors: #{total_errors}"

        # Small delay to prevent overwhelming the database
        sleep(0.1)
      end

    rescue => e
      Rails.logger.error "Migration failed: #{e.message}"
      puts "Migration failed: #{e.message}"
      raise
    ensure
      remote_conn&.close
      Rails.logger.info "Remote database connection closed"
    end

    puts "\n" + "="*60
    puts "Company migration with financial data completed!"
    puts "Total migrated: #{total_migrated}"
    puts "Total updated: #{total_updated}"
    puts "Companies with financial data: #{financial_data_copied}"
    puts "Total skipped: #{total_skipped}"
    puts "Total errors: #{total_errors}"
    puts "="*60

    # Clean up progress file on successful completion
    File.delete(progress_file) if File.exist?(progress_file) && total_errors == 0
  end

  private

  def build_company_attributes(remote_record)
    # Start with base attributes
    attrs = {
      source_registry: "companies_production",
      source_country: "NO",
      registration_country: "NO"
    }

    # Copy all available fields from remote record
    Company.column_names.each do |column_name|
      next if %w[id created_at updated_at].include?(column_name)

      # Get value from remote record
      value = remote_record[column_name]
      next if value.nil? || (value.is_a?(String) && value.strip.empty?)

      # Handle data type conversions
      case column_name
      when /date$/
        # Handle date fields
        begin
          attrs[column_name] = Date.parse(value.to_s) if value.present?
        rescue Date::Error
          Rails.logger.warn "Invalid date format for #{column_name}: #{value}"
        end
      when /updated_at$/, /created_at$/
        # Handle datetime fields
        begin
          attrs[column_name] = DateTime.parse(value.to_s) if value.present?
        rescue DateTime::Error
          Rails.logger.warn "Invalid datetime format for #{column_name}: #{value}"
        end
      when "bankruptcy", "under_liquidation", "vat_registered", "under_deletion"
        # Handle boolean fields
        attrs[column_name] = [ "true", "t", "1", 1, true ].include?(value)
      when /count$/, /employees$/, "year", "http_error", "employee_count"
        # Handle integer fields
        attrs[column_name] = value.to_i if value.to_s.match?(/^\d+$/)
      when "ordinary_result", "annual_result", "operating_revenue", "operating_costs"
        # Handle bigint financial fields
        attrs[column_name] = value.to_i if value.to_s.match?(/^-?\d+$/)
      when "revenue", "profit", "equity", "total_assets", "current_assets", "fixed_assets", "current_liabilities", "long_term_liabilities"
        # Handle decimal financial fields
        attrs[column_name] = BigDecimal(value.to_s) if value.to_s.match?(/^-?\d+\.?\d*$/)
      else
        # Handle string fields
        attrs[column_name] = value.to_s.strip
      end
    end

    attrs
  end

  def has_financial_data?(remote_record)
    # Check if the record has any financial data
    financial_fields = %w[
      ordinary_result annual_result operating_revenue operating_costs
      revenue profit equity total_assets current_assets fixed_assets
      current_liabilities long_term_liabilities financial_data
    ]

    financial_fields.any? do |field|
      value = remote_record[field]
      value.present? && value.to_s.strip != "" && value.to_s != "0"
    end
  end

  def field_mapping
    {
      # Basic company information
      "organisasjonsnummer" => "registration_number",
      "navn" => "company_name",
      "organisasjonsform_kode" => "organization_form_code",
      "organisasjonsform_beskrivelse" => "organization_form_description",

      # Industry codes
      "naeringskode1_kode" => "industry_code_1",
      "naeringskode1_beskrivelse" => "industry_code_1_description",
      "naeringskode2_kode" => "industry_code_2",
      "naeringskode2_beskrivelse" => "industry_code_2_description",
      "naeringskode3_kode" => "industry_code_3",
      "naeringskode3_beskrivelse" => "industry_code_3_description",

      # Contact information
      "hjemmeside" => "website",
      "telefon" => "phone",
      "mobiltelefon" => "mobile",
      "epostadresse" => "email",

      # Address fields - Postal
      "postadresse_adresse" => "postal_address",
      "postadresse_postnummer" => "postal_code",
      "postadresse_poststed" => "postal_city",
      "postadresse_kommune" => "postal_municipality",
      "postadresse_kommunenummer" => "postal_municipality_no",
      "postadresse_land" => "postal_country",
      "postadresse_landkode" => "postal_country_code",

      # Address fields - Business
      "forretningsadresse_adresse" => "business_address",
      "forretningsadresse_postnummer" => "business_code",
      "forretningsadresse_poststed" => "business_city",
      "forretningsadresse_kommune" => "business_municipality",
      "forretningsadresse_kommunenummer" => "business_municipality_no",
      "forretningsadresse_land" => "business_country",
      "forretningsadresse_landkode" => "business_country_code",

      # Employee information
      "antallansatte" => "employee_count",

      # Dates
      "stiftelsesdato" => "founding_date",
      "registreringsdatoenhetsregisteret" => "registration_date",
      "registreringsdatovatskattemyndighetene" => "vat_registration_date",
      "konkursdato" => "bankruptcy_date",
      "avviklingsdato" => "liquidation_date",
      "slettetdato" => "deregistration_date",

      # Status flags
      "konkurs" => "bankruptcy",
      "underavvikling" => "under_liquidation",
      "registrertimvaregisteret" => "vat_registered"
    }
  end

  def company_changed?(company, brreg_record)
    company.new_record? ||
      company.company_name != brreg_record.navn ||
      company.organization_form_description != brreg_record.organisasjonsform_beskrivelse
  end

  def update_company_attributes(company, brreg_record)
    # Set brreg_id to link back to the Brreg record
    company.brreg_id = brreg_record.id if brreg_record.respond_to?(:id)

    company.assign_attributes(
      source_country: "NO",
      source_registry: "brreg",
      source_id: brreg_record.organisasjonsnummer.to_s,
      company_name: brreg_record.navn,
      organization_form_code: brreg_record.organisasjonsform_kode,
      organization_form_description: brreg_record.organisasjonsform_beskrivelse,
      primary_industry_code: brreg_record.naeringskode1_kode,
      primary_industry_description: brreg_record.naeringskode1_beskrivelse,
      website: brreg_record.hjemmeside,
      email: safe_attribute(brreg_record, :epost) || safe_attribute(brreg_record, :epostadresse),
      phone: brreg_record.telefon,
      mobile: safe_attribute(brreg_record, :mobiltelefon) || safe_attribute(brreg_record, :mobil),
      postal_address: safe_attribute(brreg_record, :forretningsadresse) || safe_attribute(brreg_record, :forretningsadresse_adresse),
      postal_city: brreg_record.forretningsadresse_poststed,
      postal_code: brreg_record.forretningsadresse_postnummer,
      postal_municipality: brreg_record.forretningsadresse_kommune,
      postal_country: brreg_record.forretningsadresse_land,
      postal_country_code: safe_attribute(brreg_record, :forretningsadresse_landkode),
      has_registered_employees: safe_attribute(brreg_record, :harregistrertantallansatte) == "true",
      employee_count: brreg_record.antallansatte&.to_i,
      employee_registration_date_registry: parse_date(safe_attribute(brreg_record, :registreringsdatoantallansatteenhetsregisteret)),
      employee_registration_date_nav: parse_date(safe_attribute(brreg_record, :registreringsdatoantallansattenavaaregisteret))
    )
  end

  def safe_attribute(record, attribute)
    record.respond_to?(attribute) ? record.send(attribute) : nil
  end

  def parse_date(date_str)
    Date.parse(date_str) rescue nil
  end
end
