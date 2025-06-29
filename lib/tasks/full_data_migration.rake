namespace :data do
  desc "Migrate Users, Domains, and Service Audit Logs from production to localhost"
  task migrate_all_from_production: :environment do
    require "pg"

    puts "Starting full data migration from app.connectica.no to localhost..."
    puts "This will migrate: Users, Domains, and Service Audit Logs"
    puts "="*60

    # Database connection settings for remote production database
    remote_db_config = {
      host: "app.connectica.no",
      port: 5432,
      dbname: "b2b_production",
      user: "benjamin",
      password: "Charcoal2020!"
    }

    batch_size = ENV["BATCH_SIZE"]&.to_i || 1000

    begin
      # Connect to remote database
      remote_conn = PG.connect(remote_db_config)
      puts "Connected to remote production database at app.connectica.no"

      # Migrate Users
      migrate_users(remote_conn, batch_size)
      puts "\n" + "-"*60 + "\n"

      # Migrate Domains
      migrate_domains(remote_conn, batch_size)
      puts "\n" + "-"*60 + "\n"

      # Migrate Service Audit Logs
      migrate_service_audit_logs(remote_conn, batch_size)

    rescue => e
      Rails.logger.error "Migration failed: #{e.message}"
      puts "Migration failed: #{e.message}"
      raise
    ensure
      remote_conn&.close
      puts "\nRemote database connection closed"
    end

    puts "\n" + "="*60
    puts "Full data migration completed!"
    puts "="*60
  end

  private

  def migrate_users(remote_conn, batch_size)
    puts "\nMigrating Users..."

    # Progress tracking
    progress_file = Rails.root.join("tmp", "user_migration_progress.txt")
    start_from = 0

    if File.exist?(progress_file)
      start_from = File.read(progress_file).strip.to_i
      puts "Resuming from user ID: #{start_from}"
    end

    total_migrated = 0
    total_skipped = 0
    total_errors = 0

    # Get total count
    total_count_result = remote_conn.exec("SELECT COUNT(*) FROM users WHERE id > #{start_from}")
    total_count = total_count_result[0]["count"].to_i
    puts "Total user records to process: #{total_count}"

    local_count_before = User.count
    puts "Local users before migration: #{local_count_before}"

    loop do
      query = <<-SQL
        SELECT * FROM users
        WHERE id > #{start_from}
        ORDER BY id
        LIMIT #{batch_size}
      SQL

      result = remote_conn.exec(query)
      break if result.ntuples == 0

      ActiveRecord::Base.transaction do
        result.each do |remote_record|
          begin
            user_id = remote_record["id"]
            email = remote_record["email"]

            # Check if user already exists by email
            if email.present? && User.exists?(email: email)
              Rails.logger.debug "Skipping existing user: #{email}"
              total_skipped += 1
              next
            end

            # Map user attributes
            user_attrs = {}

            # Copy all fields that exist in both remote and local User model
            remote_record.each do |key, value|
              if User.column_names.include?(key) && key != "id"
                case key
                when "created_at", "updated_at", "remember_created_at", "current_sign_in_at", "last_sign_in_at"
                  user_attrs[key] = Time.parse(value) if value.present?
                when "sign_in_count", "failed_attempts"
                  user_attrs[key] = value.to_i if value.present?
                when "admin"
                  user_attrs[key] = value == "t" || value == true
                else
                  user_attrs[key] = value
                end
              end
            end

            # Don't copy encrypted password directly - set a temporary one
            if user_attrs["encrypted_password"].blank?
              user_attrs["password"] = "TempPassword123!"
              user_attrs["password_confirmation"] = "TempPassword123!"
            end

            # Create user
            user = User.create!(user_attrs.except("encrypted_password"))
            Rails.logger.debug "✓ Created user: #{email}"
            total_migrated += 1

            # Update progress
            File.write(progress_file, user_id)

          rescue => e
            Rails.logger.error "Error processing user ID #{remote_record['id']}: #{e.message}"
            total_errors += 1
            next
          end
        end
      end

      # Update start_from for next batch
      last_record = result[result.ntuples - 1]
      start_from = last_record["id"].to_i

      puts "Users batch complete. Migrated: #{total_migrated}, Skipped: #{total_skipped}, Errors: #{total_errors}"
      sleep(0.1)
    end

    local_count_after = User.count
    puts "\nUser migration completed!"
    puts "Total migrated: #{total_migrated}"
    puts "Total skipped: #{total_skipped}"
    puts "Total errors: #{total_errors}"
    puts "Local users before: #{local_count_before}"
    puts "Local users after: #{local_count_after}"
    puts "Net increase: #{local_count_after - local_count_before}"

    # Clean up progress file on successful completion
    File.delete(progress_file) if File.exist?(progress_file) && total_errors == 0
  end

  def migrate_domains(remote_conn, batch_size)
    puts "\nMigrating Domains..."

    # Progress tracking
    progress_file = Rails.root.join("tmp", "domain_migration_progress.txt")
    start_from = 0

    if File.exist?(progress_file)
      start_from = File.read(progress_file).strip.to_i
      puts "Resuming from domain ID: #{start_from}"
    end

    total_migrated = 0
    total_skipped = 0
    total_errors = 0

    # Get total count
    total_count_result = remote_conn.exec("SELECT COUNT(*) FROM domains WHERE id > #{start_from}")
    total_count = total_count_result[0]["count"].to_i
    puts "Total domain records to process: #{total_count}"

    local_count_before = Domain.count
    puts "Local domains before migration: #{local_count_before}"

    # Create a mapping of company registration numbers to local IDs
    company_mapping = {}
    Company.pluck(:registration_number, :id).each do |reg_num, id|
      company_mapping[reg_num] = id if reg_num.present?
    end

    loop do
      query = <<-SQL
        SELECT d.*, c.registration_number as company_reg_number
        FROM domains d
        LEFT JOIN companies c ON d.company_id = c.id
        WHERE d.id > #{start_from}
        ORDER BY d.id
        LIMIT #{batch_size}
      SQL

      result = remote_conn.exec(query)
      break if result.ntuples == 0

      ActiveRecord::Base.transaction do
        result.each do |remote_record|
          begin
            domain_id = remote_record["id"]
            domain_name = remote_record["domain_name"]

            # Check if domain already exists
            if domain_name.present? && Domain.exists?(domain_name: domain_name)
              Rails.logger.debug "Skipping existing domain: #{domain_name}"
              total_skipped += 1
              next
            end

            # Map domain attributes
            domain_attrs = {}

            # Copy all fields that exist in both remote and local Domain model
            remote_record.each do |key, value|
              if Domain.column_names.include?(key) && key != "id" && key != "company_id"
                case key
                when "created_at", "updated_at", "dns_tested_at", "web_content_extracted_at",
                     "ssl_checked_at", "last_tested_at", "whois_checked_at", "mail_server_checked_at",
                     "queue_processing_started_at", "queue_processing_completed_at"
                  domain_attrs[key] = Time.parse(value) if value.present?
                when "queue_priority", "subdomain_count", "retry_count"
                  domain_attrs[key] = value.to_i if value.present?
                when "has_mx_records", "ssl_valid", "has_spf_record", "has_dmarc_record",
                     "has_dkim_record", "nameservers_responsive", "website_accessible",
                     "has_ssl_certificate", "ssl_certificate_valid", "active", "queue_active"
                  domain_attrs[key] = value == "t" || value == true
                when "ssl_expiry_date"
                  begin
                    domain_attrs[key] = Date.parse(value) if value.present?
                  rescue Date::Error
                    Rails.logger.warn "Invalid date format for ssl_expiry_date: #{value}"
                  end
                else
                  domain_attrs[key] = value
                end
              end
            end

            # Map company_id using registration number
            if remote_record["company_reg_number"].present?
              local_company_id = company_mapping[remote_record["company_reg_number"]]
              if local_company_id
                domain_attrs["company_id"] = local_company_id
              else
                Rails.logger.warn "Could not find local company for registration number: #{remote_record['company_reg_number']}"
              end
            end

            # Create domain
            domain = Domain.create!(domain_attrs)
            Rails.logger.debug "✓ Created domain: #{domain_name}"
            total_migrated += 1

            # Update progress
            File.write(progress_file, domain_id)

          rescue => e
            Rails.logger.error "Error processing domain ID #{remote_record['id']}: #{e.message}"
            total_errors += 1
            next
          end
        end
      end

      # Update start_from for next batch
      last_record = result[result.ntuples - 1]
      start_from = last_record["id"].to_i

      puts "Domains batch complete. Migrated: #{total_migrated}, Skipped: #{total_skipped}, Errors: #{total_errors}"
      sleep(0.1)
    end

    local_count_after = Domain.count
    puts "\nDomain migration completed!"
    puts "Total migrated: #{total_migrated}"
    puts "Total skipped: #{total_skipped}"
    puts "Total errors: #{total_errors}"
    puts "Local domains before: #{local_count_before}"
    puts "Local domains after: #{local_count_after}"
    puts "Net increase: #{local_count_after - local_count_before}"

    # Clean up progress file on successful completion
    File.delete(progress_file) if File.exist?(progress_file) && total_errors == 0
  end

  def migrate_service_audit_logs(remote_conn, batch_size)
    puts "\nMigrating Service Audit Logs..."

    # Progress tracking
    progress_file = Rails.root.join("tmp", "service_audit_log_migration_progress.txt")
    start_from = 0

    if File.exist?(progress_file)
      start_from = File.read(progress_file).strip.to_i
      puts "Resuming from service audit log ID: #{start_from}"
    end

    total_migrated = 0
    total_skipped = 0
    total_errors = 0

    # Get total count
    total_count_result = remote_conn.exec("SELECT COUNT(*) FROM service_audit_logs WHERE id > #{start_from}")
    total_count = total_count_result[0]["count"].to_i
    puts "Total service audit log records to process: #{total_count}"

    local_count_before = ServiceAuditLog.count
    puts "Local service audit logs before migration: #{local_count_before}"

    # Create mappings for polymorphic associations
    domain_mapping = Domain.pluck(:domain_name, :id).to_h
    company_mapping = {}
    Company.pluck(:registration_number, :id).each do |reg_num, id|
      company_mapping[reg_num] = id if reg_num.present?
    end

    loop do
      query = <<-SQL
        SELECT sal.*,
               CASE#{' '}
                 WHEN sal.auditable_type = 'Domain' THEN d.domain_name
                 WHEN sal.auditable_type = 'Company' THEN c.registration_number
               END as auditable_identifier
        FROM service_audit_logs sal
        LEFT JOIN domains d ON sal.auditable_type = 'Domain' AND sal.auditable_id = d.id
        LEFT JOIN companies c ON sal.auditable_type = 'Company' AND sal.auditable_id = c.id
        WHERE sal.id > #{start_from}
        ORDER BY sal.id
        LIMIT #{batch_size}
      SQL

      result = remote_conn.exec(query)
      break if result.ntuples == 0

      ActiveRecord::Base.transaction do
        result.each do |remote_record|
          begin
            log_id = remote_record["id"]

            # Map service audit log attributes
            log_attrs = {}

            # Copy all fields that exist in both remote and local ServiceAuditLog model
            remote_record.each do |key, value|
              if ServiceAuditLog.column_names.include?(key) &&
                 key != "id" && key != "auditable_id" && key != "auditable_identifier"
                case key
                when "created_at", "updated_at", "started_at", "completed_at"
                  log_attrs[key] = Time.parse(value) if value.present?
                when "status", "execution_time_ms"
                  log_attrs[key] = value.to_i if value.present?
                when "metadata", "columns_affected"
                  # Parse JSON fields
                  begin
                    log_attrs[key] = JSON.parse(value) if value.present?
                  rescue JSON::ParserError
                    Rails.logger.warn "Invalid JSON for #{key}: #{value}"
                    log_attrs[key] = key == "metadata" ? { "status" => "migrated" } : [ "unspecified" ]
                  end
                else
                  log_attrs[key] = value
                end
              end
            end

            # Map auditable polymorphic association
            auditable_type = remote_record["auditable_type"]
            auditable_identifier = remote_record["auditable_identifier"]

            if auditable_type.present? && auditable_identifier.present?
              case auditable_type
              when "Domain"
                local_id = domain_mapping[auditable_identifier]
                if local_id
                  log_attrs["auditable_type"] = "Domain"
                  log_attrs["auditable_id"] = local_id
                else
                  Rails.logger.warn "Could not find local domain: #{auditable_identifier}"
                  total_skipped += 1
                  next
                end
              when "Company"
                local_id = company_mapping[auditable_identifier]
                if local_id
                  log_attrs["auditable_type"] = "Company"
                  log_attrs["auditable_id"] = local_id
                else
                  Rails.logger.warn "Could not find local company: #{auditable_identifier}"
                  total_skipped += 1
                  next
                end
              else
                Rails.logger.warn "Unknown auditable type: #{auditable_type}"
                total_skipped += 1
                next
              end
            else
              total_skipped += 1
              next
            end

            # Ensure required fields have defaults
            log_attrs["metadata"] ||= { "status" => "migrated" }
            log_attrs["columns_affected"] ||= [ "unspecified" ]

            # Create service audit log
            log = ServiceAuditLog.create!(log_attrs)
            Rails.logger.debug "✓ Created service audit log for #{auditable_type} #{auditable_identifier}"
            total_migrated += 1

            # Update progress
            File.write(progress_file, log_id)

          rescue => e
            Rails.logger.error "Error processing service audit log ID #{remote_record['id']}: #{e.message}"
            Rails.logger.error e.backtrace.first(3).join("\n") if ENV["DEBUG"]
            total_errors += 1
            next
          end
        end
      end

      # Update start_from for next batch
      last_record = result[result.ntuples - 1]
      start_from = last_record["id"].to_i

      puts "Service audit logs batch complete. Migrated: #{total_migrated}, Skipped: #{total_skipped}, Errors: #{total_errors}"
      sleep(0.1)
    end

    local_count_after = ServiceAuditLog.count
    puts "\nService Audit Log migration completed!"
    puts "Total migrated: #{total_migrated}"
    puts "Total skipped: #{total_skipped}"
    puts "Total errors: #{total_errors}"
    puts "Local service audit logs before: #{local_count_before}"
    puts "Local service audit logs after: #{local_count_after}"
    puts "Net increase: #{local_count_after - local_count_before}"

    # Clean up progress file on successful completion
    File.delete(progress_file) if File.exist?(progress_file) && total_errors == 0
  end
end
