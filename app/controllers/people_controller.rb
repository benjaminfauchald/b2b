# frozen_string_literal: true

class PeopleController < ApplicationController
  before_action :authenticate_user!
  before_action :set_person, only: %i[show edit update destroy queue_single_email_extraction queue_single_social_media_extraction service_status verify_email]
  skip_before_action :verify_authenticity_token, only: [ :queue_profile_extraction, :queue_email_extraction, :queue_social_media_extraction, :queue_single_profile_extraction, :queue_single_email_extraction, :queue_single_social_media_extraction ]

  def index
    people_scope = Person.includes(:service_audit_logs, :company)
                        .order(created_at: :desc)

    if params[:search].present?
      people_scope = people_scope.where(
        "name ILIKE :search OR company_name ILIKE :search OR email ILIKE :search",
        search: "%#{params[:search]}%"
      )
    end

    if params[:filter] == "with_profiles"
      people_scope = people_scope.with_profile_data
    elsif params[:filter] == "with_emails"
      people_scope = people_scope.with_email_data
    elsif params[:filter] == "with_social_media"
      people_scope = people_scope.with_social_media_data
    elsif params[:filter] == "needs_extraction"
      people_scope = people_scope.needs_profile_extraction
    end

    if params[:import_tag].present?
      people_scope = people_scope.imported_with_tag(params[:import_tag])
    end

    @pagy, @people = pagy(people_scope)
    @queue_stats = get_queue_stats
    
    # Calculate statistics for the header
    @total_people_count = Person.count
    @total_companies_count = Person.where.not(company_name: [nil, ""]).distinct.count(:company_name)
    @average_people_per_company = @total_companies_count > 0 ? (@total_people_count.to_f / @total_companies_count).ceil : 0
  end

  def show
    @service_audit_logs = @person.service_audit_logs
                                .order(created_at: :desc)
                                .limit(10)
  end

  def new
    @person = Person.new
  end

  def edit
  end

  def create
    @person = Person.new(person_params)

    if @person.save
      redirect_to @person, notice: "Person was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    # Check if this is an inline edit (AJAX request)
    if request.xhr? || request.format.json?
      # Handle inline editing with audit logging
      allowed_fields = %w[email phone]
      field_to_update = person_params.keys.first.to_s

      if allowed_fields.include?(field_to_update)
        old_value = @person.send(field_to_update)
        new_value = person_params[field_to_update]

        if @person.update(person_params)
          # Clear email verification if email was changed
          if field_to_update == "email" && old_value != new_value
            @person.update_columns(
              email_verification_status: "unverified",
              email_verification_confidence: 0.0,
              email_verification_checked_at: nil,
              email_verification_metadata: {}
            )
          end

          # Log the user update to ServiceAuditLog
          ServiceAuditLog.create!(
            auditable: @person,
            service_name: "user_update",
            status: :success,
            started_at: Time.current,
            completed_at: Time.current,
            table_name: "people",
            record_id: @person.id.to_s,
            operation_type: "update",
            columns_affected: [ field_to_update ],
            execution_time_ms: 0,
            metadata: {
              field: field_to_update,
              old_value: old_value,
              new_value: new_value,
              updated_by: current_user.email,
              updated_at: Time.current.iso8601
            }
          )

          render json: { success: true, message: "Field updated successfully" }
        else
          render json: { success: false, error: @person.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
      else
        render json: { success: false, error: "Field not allowed for inline editing" },
               status: :forbidden
      end
    else
      # Regular form submission
      # Get the list of changed fields for audit logging
      changed_fields = []
      old_values = {}

      allowed_fields = %w[email phone]

      # Track which allowed fields are being changed
      allowed_fields.each do |field|
        if person_params.key?(field) && @person.send(field) != person_params[field]
          changed_fields << field
          old_values[field] = @person.send(field)
        end
      end

      if @person.update(person_params)
        # Clear email verification if email was changed
        if changed_fields.include?("email")
          @person.update_columns(
            email_verification_status: "unverified",
            email_verification_confidence: 0.0,
            email_verification_checked_at: nil,
            email_verification_metadata: {}
          )
        end

        # Create audit log only if allowed fields were changed
        if changed_fields.any?
          metadata = {
            fields_changed: changed_fields,
            changes: {},
            updated_by: current_user.email,
            updated_at: Time.current.iso8601
          }

          # Add old and new values for each changed field
          changed_fields.each do |field|
            metadata[:changes][field] = {
              old_value: old_values[field],
              new_value: @person.send(field)
            }
          end

          ServiceAuditLog.create!(
            auditable: @person,
            service_name: "user_update",
            status: :success,
            started_at: Time.current,
            completed_at: Time.current,
            table_name: "people",
            record_id: @person.id.to_s,
            operation_type: "update",
            columns_affected: changed_fields,
            execution_time_ms: 0,
            metadata: metadata
          )
        end

        redirect_to @person, notice: "Person was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  def destroy
    @person.destroy!
    redirect_to people_url, notice: "Person was successfully destroyed."
  end

  # POST /people/queue_profile_extraction
  def queue_profile_extraction
    unless ServiceConfiguration.active?("person_profile_extraction")
      render json: { success: false, message: "Profile extraction service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 persons at once" }
      return
    end

    # Get companies that need processing for profile extraction
    available_companies = Company.needing_service("person_profile_extraction")
    available_count = available_companies.count

    # Check if we have enough companies to process
    if available_count == 0
      render json: {
        success: false,
        message: "No companies with valid LinkedIn URLs available for profile extraction",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} companies available for profile extraction, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    companies = available_companies.limit(count)

    queued = 0
    companies.each do |company|
      PersonProfileExtractionWorker.perform_async(company.id)
      queued += 1
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("person_service_stats_data")

    render json: {
      success: true,
      message: "Queued #{queued} companies for profile extraction",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /people/queue_email_extraction
  def queue_email_extraction
    unless ServiceConfiguration.active?("person_email_extraction")
      render json: { success: false, message: "Email extraction service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 persons at once" }
      return
    end

    # Get available persons that need processing
    available_persons = Person.needing_service("person_email_extraction")
    available_count = available_persons.count

    # Check if we have enough persons to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No persons need email extraction at this time",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} persons need email extraction, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    persons = available_persons.limit(count)

    queued = 0
    persons.each do |person|
      PersonEmailExtractionWorker.perform_async(person.id)
      queued += 1
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("service_stats_data")

    render json: {
      success: true,
      message: "Queued #{queued} persons for email extraction",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /people/queue_social_media_extraction
  def queue_social_media_extraction
    unless ServiceConfiguration.active?("person_social_media_extraction")
      render json: { success: false, message: "Social media extraction service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 persons at once" }
      return
    end

    # Get available persons that need processing
    available_persons = Person.needing_service("person_social_media_extraction")
    available_count = available_persons.count

    # Check if we have enough persons to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No persons need social media extraction at this time",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} persons need social media extraction, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    persons = available_persons.limit(count)

    queued = 0
    persons.each do |person|
      PersonSocialMediaExtractionWorker.perform_async(person.id)
      queued += 1
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("service_stats_data")

    render json: {
      success: true,
      message: "Queued #{queued} persons for social media extraction",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # GET /people/service_stats
  def service_stats
    respond_to do |format|
      format.turbo_stream do
        # Cache the stats for 1 second to ensure real-time updates
        stats_data = Rails.cache.fetch("person_service_stats_data", expires_in: 1.second) do
          calculate_service_stats
        end

        queue_stats = get_queue_stats

        render turbo_stream: [
          turbo_stream.replace("person_profile_extraction_stats",
            partial: "people/service_stats",
            locals: {
              service_name: "person_profile_extraction",
              service_title: "Profile Extraction",
              companies_needing: stats_data[:profile_needing],
              companies_potential: stats_data[:profile_potential],
              queue_depth: queue_stats["person_profile_extraction"] || 0
            }
          ),
          turbo_stream.replace("person_email_extraction_stats",
            partial: "people/service_stats",
            locals: {
              service_name: "person_email_extraction",
              service_title: "Email Extraction",
              people_needing: stats_data[:email_needing],
              queue_depth: queue_stats["person_email_extraction"] || 0
            }
          ),
          turbo_stream.replace("person_social_media_extraction_stats",
            partial: "people/service_stats",
            locals: {
              service_name: "person_social_media_extraction",
              service_title: "Social Media Extraction",
              people_needing: stats_data[:social_media_needing],
              queue_depth: queue_stats["person_social_media_extraction"] || 0
            }
          ),
          turbo_stream.replace("people_queue_statistics",
            partial: "people/queue_statistics",
            locals: { queue_stats: queue_stats }
          )
        ]
      end
    end
  end

  # POST /people/queue_single_profile_extraction
  # This is called from company pages to extract profiles for a specific company
  def queue_single_profile_extraction
    unless ServiceConfiguration.active?("person_profile_extraction")
      render json: { success: false, message: "Profile extraction service is disabled" }
      return
    end

    company_id = params[:company_id]
    unless company_id.present?
      render json: { success: false, message: "Company ID is required" }
      return
    end

    company = Company.find_by(id: company_id)
    unless company
      render json: { success: false, message: "Company not found" }
      return
    end

    unless company.best_linkedin_url.present?
      render json: { success: false, message: "Company has no valid LinkedIn URL" }
      return
    end

    begin
      job_id = PersonProfileExtractionWorker.perform_async(company.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("person_service_stats_data")

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Profile extraction queued for #{company.company_name}",
            company_id: company.id,
            service: "profile_extraction",
            job_id: job_id,
            worker: "PersonProfileExtractionWorker"
          }
        end
        format.html do
          redirect_to company_path(company), notice: "Profile extraction queued for #{company.company_name}"
        end
      end
    rescue => e
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            message: "Failed to queue profile extraction: #{e.message}"
          }
        end
        format.html do
          redirect_to company_path(company), alert: "Failed to queue profile extraction: #{e.message}"
        end
      end
    end
  end

  # POST /people/:id/queue_single_email_extraction
  def queue_single_email_extraction
    unless ServiceConfiguration.active?("person_email_extraction")
      render json: { success: false, message: "Email extraction service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @person,
        service_name: "person_email_extraction",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @person.class.table_name,
        record_id: @person.id.to_s,
        columns_affected: [ "email", "email_data" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = PersonEmailExtractionWorker.perform_async(@person.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("person_service_stats_data")

      render json: {
        success: true,
        message: "Person queued for email extraction",
        person_id: @person.id,
        service: "email_extraction",
        job_id: job_id,
        worker: "PersonEmailExtractionWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue person for email extraction: #{e.message}"
      }
    end
  end

  # POST /people/:id/queue_single_social_media_extraction
  def queue_single_social_media_extraction
    unless ServiceConfiguration.active?("person_social_media_extraction")
      render json: { success: false, message: "Social media extraction service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @person,
        service_name: "person_social_media_extraction",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @person.class.table_name,
        record_id: @person.id.to_s,
        columns_affected: [ "social_media_data" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = PersonSocialMediaExtractionWorker.perform_async(@person.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("person_service_stats_data")

      render json: {
        success: true,
        message: "Person queued for social media extraction",
        person_id: @person.id,
        service: "social_media_extraction",
        job_id: job_id,
        worker: "PersonSocialMediaExtractionWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue person for social media extraction: #{e.message}"
      }
    end
  end

  # POST /people/:id/verify_email
  def verify_email
    Rails.logger.info "Email verification requested for person #{@person.id}"

    unless ServiceConfiguration.active?("local_email_verify")
      render json: { success: false, error: "Email verification service is disabled" }
      return
    end

    unless @person.email.present?
      render json: { success: false, error: "Person has no email address" }
      return
    end

    begin
      # Run email verification synchronously for immediate feedback
      service = People::LocalEmailVerifyService.new(person: @person)
      result = service.perform

      Rails.logger.info "Email verification result: #{result.success?} - #{result.message}"

      if result.success?
        # Reload person to get updated data
        @person.reload

        Rails.logger.info "Person verification status updated: #{@person.email_verification_status} (#{@person.email_verification_confidence})"

        render json: {
          success: true,
          message: result.message,
          status: @person.email_verification_status,
          confidence: @person.email_verification_confidence,
          data: result.data
        }
      else
        render json: {
          success: false,
          error: result.error || "Email verification failed"
        }
      end
    rescue => e
      Rails.logger.error "Email verification error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        success: false,
        error: "An error occurred during verification"
      }
    end
  end

  # GET /people/:id/service_status - Check if a service has completed for this person
  def service_status
    service_type = params[:service]

    # Map service type to service name
    service_name = case service_type
    when "email_extraction"
      "person_email_extraction"
    when "social_media_extraction"
      "person_social_media_extraction"
    when "profile_extraction"
      "person_profile_extraction"
    else
      service_type
    end

    # Check for recent successful completion
    recent_completion = @person.service_audit_logs
                              .where(service_name: service_name)
                              .where("completed_at > ?", 2.minutes.ago)
                              .where(status: "success")
                              .exists?

    # Also check if there are any pending jobs (not started yet)
    pending_jobs = @person.service_audit_logs
                          .where(service_name: service_name)
                          .where("started_at > ?", 2.minutes.ago)
                          .where(status: "pending")
                          .exists?

    render json: {
      completed: recent_completion,
      pending: pending_jobs,
      service: service_name,
      timestamp: Time.current
    }
  end

  # GET /people/import
  def import_csv
    # Show the CSV import form
  end

  # POST /people/import
  def process_import
    request_start_time = Time.current
    Rails.logger.info "\n" + "="*60
    Rails.logger.info "🚀 PERSON CSV IMPORT REQUEST START: #{request_start_time}"
    Rails.logger.info "="*60

    Rails.logger.info "📋 REQUEST DETAILS:"
    Rails.logger.info "  - User ID: #{current_user&.id}"
    Rails.logger.info "  - User email: #{current_user&.email}"
    Rails.logger.info "  - Request IP: #{request.remote_ip}"
    Rails.logger.info "  - Params present: #{params.keys}"
    Rails.logger.info "  - CSV file present: #{params[:csv_file].present?}"
    Rails.logger.info "  - Email validation enabled: #{params[:validate_emails] == '1' || params[:validate_emails] == 'true'}"

    if params[:csv_file]
      Rails.logger.info "📁 FILE DETAILS:"
      Rails.logger.info "  - File class: #{params[:csv_file].class}"
      Rails.logger.info "  - File size: #{params[:csv_file].respond_to?(:size) ? "#{params[:csv_file].size} bytes (#{(params[:csv_file].size / 1024.0 / 1024.0).round(2)} MB)" : 'N/A'}"
      Rails.logger.info "  - File name: #{params[:csv_file].respond_to?(:original_filename) ? params[:csv_file].original_filename : 'N/A'}"
      Rails.logger.info "  - Content type: #{params[:csv_file].respond_to?(:content_type) ? params[:csv_file].content_type : 'N/A'}"
    end

    unless params[:csv_file].present?
      redirect_to import_people_path, alert: "Please select a CSV file to upload."
      return
    end

    # Check rate limiting (simple session-based approach)
    if session[:last_import_at] && session[:last_import_at] > 5.seconds.ago
      redirect_to import_people_path, alert: "Please wait a moment before importing again."
      return
    end

    begin
      # Check file size and decide processing method
      file_size_mb = (params[:csv_file].size / 1024.0 / 1024.0).round(2)
      large_file_threshold = 5.0 # MB

      Rails.logger.info "\n🔍 PROCESSING DECISION:"
      Rails.logger.info "  - File size: #{file_size_mb} MB"
      Rails.logger.info "  - Large file threshold: #{large_file_threshold} MB"
      Rails.logger.info "  - Will use: #{file_size_mb > large_file_threshold ? 'BACKGROUND PROCESSING' : 'SYNCHRONOUS PROCESSING'}"

      if file_size_mb > large_file_threshold
        # Large file - use background job
        Rails.logger.info "\n🚀 QUEUEING BACKGROUND JOB:"

        # Create unique import ID
        import_id = SecureRandom.uuid
        Rails.logger.info "  - Import ID: #{import_id}"

        # Save file to temporary location with secure filename
        original_filename = params[:csv_file].respond_to?(:original_filename) ? params[:csv_file].original_filename : "import.csv"
        # Use only the import_id for the filename to prevent any path traversal attacks
        temp_file_path = Rails.root.join("tmp", "person_import_#{import_id}.csv")
        File.open(temp_file_path, "wb") do |file|
          file.write(params[:csv_file].read)
        end
        Rails.logger.info "  - Temporary file saved: #{temp_file_path}"

        # Queue the background job
        PersonImportJob.perform_later(
          temp_file_path.to_s,
          current_user.id,
          original_filename,
          import_id,
          params[:validate_emails] == "1" || params[:validate_emails] == "true"
        )

        Rails.logger.info "  - Background job queued successfully"

        # Store import ID in session for status checking
        session[:import_id] = import_id
        session[:import_status] = "queued"
        session[:import_started_at] = Time.current

        total_request_duration = Time.current - request_start_time
        Rails.logger.info "\n📈 BACKGROUND JOB REQUEST SUMMARY:"
        Rails.logger.info "  - Total request time: #{total_request_duration.round(4)} seconds"
        Rails.logger.info "  - Processing queued in background"

        respond_to do |format|
          format.html { redirect_to import_status_people_path }
          format.json { render json: { status: 'success', redirect_url: import_status_people_path } }
        end
      else
        # Small file - process synchronously
        Rails.logger.info "\n🔧 SYNCHRONOUS PROCESSING:"

        # Service instantiation
        service_creation_start = Time.current
        Rails.logger.info "  - Creating service..."

        service = PersonImportService.new(
          file: params[:csv_file],
          user: current_user,
          validate_emails: params[:validate_emails] == "1" || params[:validate_emails] == "true"
        )

        service_creation_duration = Time.current - service_creation_start
        Rails.logger.info "  - Service created in #{service_creation_duration.round(4)} seconds"

        # Service execution
        service_execution_start = Time.current
        Rails.logger.info "  - Executing service..."

        result = service.perform

        service_execution_duration = Time.current - service_execution_start
        Rails.logger.info "  - Service executed in #{service_execution_duration.round(4)} seconds"

        # Update session tracking
        session[:last_import_at] = Time.current

        total_request_duration = Time.current - request_start_time

        Rails.logger.info "\n📈 SYNCHRONOUS REQUEST SUMMARY:"
        Rails.logger.info "  - Total request time: #{total_request_duration.round(4)} seconds"
        Rails.logger.info "  - Service creation time: #{service_creation_duration.round(4)} seconds"
        Rails.logger.info "  - Service execution time: #{service_execution_duration.round(4)} seconds"

        if result.success?
          Rails.logger.info "  - Import successful!"
          Rails.logger.info "  - Imported: #{result.data[:imported]}"
          Rails.logger.info "  - Updated: #{result.data[:updated]}"
          Rails.logger.info "  - Failed: #{result.data[:failed]}"
          Rails.logger.info "  - Duplicates: #{result.data[:duplicates]}"

          # Store result directly in session (like domains controller)
          # Limit the data to prevent session overflow
          import_result_data = result.data[:result]
          session_data = {
            success: true,
            imported_count: import_result_data.imported_count,
            updated_count: import_result_data.updated_count,
            failed_count: import_result_data.failed_count,
            duplicate_count: import_result_data.duplicate_count,
            total_count: import_result_data.total_count,
            summary_message: import_result_data.summary_message,
            email_verification_summary: import_result_data.email_verification_summary,
            processing_time: import_result_data.processing_time,
            people_per_second: import_result_data.people_per_second,
            # Limit arrays to prevent session overflow
            imported_people: import_result_data.imported_people.first(10),
            updated_people: import_result_data.updated_people.first(10),
            failed_people: import_result_data.failed_people.first(10),
            duplicate_people: import_result_data.duplicate_people.first(10),
            csv_errors: import_result_data.csv_errors.first(5)
          }
          
          session[:last_import_results] = session_data
          session[:last_import_time] = Time.current

          # Clean up progress data
          Rails.cache.delete("person_import_progress_#{current_user.id}")

          Rails.logger.info "🎯 ABOUT TO REDIRECT TO RESULTS PAGE"
          Rails.logger.info "  - Session data stored: #{session[:last_import_results].present?}"
          Rails.logger.info "  - Import results path: #{import_results_people_path}"
          
          # Always redirect to results page after successful import
          redirect_to import_results_people_path, notice: "Person import completed successfully!"
          
          Rails.logger.info "🎯 REDIRECT CALLED"
        else
          Rails.logger.info "  - Import failed: #{result.error}"
          respond_to do |format|
            format.html { redirect_to import_people_path, alert: result.error }
            format.json { render json: { status: 'error', message: result.error }, status: :unprocessable_entity }
          end
        end
      end

    rescue => e
      Rails.logger.error "❌ PERSON IMPORT ERROR: #{e.message}"
      Rails.logger.error "❌ BACKTRACE: #{e.backtrace.join("\n")}"

      respond_to do |format|
        format.html { redirect_to import_people_path, alert: "Import failed: #{e.message}" }
        format.json { render json: { status: 'error', message: "Import failed: #{e.message}" }, status: :internal_server_error }
      end
    end
  end

  # GET /people/import_results
  def import_results
    import_results = session[:last_import_results]
    import_time = session[:last_import_time]

    if import_results.nil?
      redirect_to import_people_path, alert: "No import results found."
      return
    end

    # Convert session data to OpenStruct for easier access in view
    @import_result = OpenStruct.new(import_results)
    @import_time = import_time
  end

  # GET /people/import_progress (AJAX endpoint)
  def import_progress
    progress_key = "person_import_progress_#{current_user.id}"
    progress_data = Rails.cache.read(progress_key)

    # Rails.logger.debug "Progress request for user #{current_user.id}: #{progress_data.inspect}"

    if progress_data
      # Check if import is complete
      is_complete = progress_data[:percent] == 100 || 
                    (progress_data[:current] == progress_data[:total] && progress_data[:total] > 0)
      
      render json: {
        status: is_complete ? "complete" : "in_progress",
        current: progress_data[:current],
        total: progress_data[:total],
        percent: progress_data[:percent],
        message: progress_data[:message],
        updated_at: progress_data[:updated_at]
      }
    else
      render json: {
        status: "not_found",
        message: "No import progress found"
      }
    end
  end

  # GET /people/import_status
  def import_status
    @import_id = session[:import_id]
    @import_status = session[:import_status]
    @import_started_at = session[:import_started_at]

    if @import_id.nil?
      redirect_to import_people_path, alert: "No import in progress."
      nil
    end
  end

  # GET /people/check_import_status
  def check_import_status
    import_id = session[:import_id]

    if import_id.nil?
      render json: { error: "No import ID found" }, status: :not_found
      return
    end

    # Check if the background job has completed by looking for a result file
    result_file_path = Rails.root.join("tmp", "person_import_result_#{import_id}.json")

    if File.exist?(result_file_path)
      # Job completed - read the result
      result_data = JSON.parse(File.read(result_file_path))

      # Clean up the result file
      File.delete(result_file_path)

      # Store result in session
      session[:last_import_result] = result_data
      session[:import_status] = "completed"

      render json: {
        status: "completed",
        result: result_data,
        redirect_url: import_results_people_path
      }
    else
      # Job still running
      render json: {
        status: "processing",
        started_at: session[:import_started_at]
      }
    end
  end

  # GET /people/template
  def download_template
    csv_content = generate_person_csv_template

    respond_to do |format|
      format.csv do
        send_data csv_content,
                  filename: "person_import_template.csv",
                  type: "text/csv",
                  disposition: "attachment"
      end
    end
  end

  # GET /people/export_errors
  def export_errors
    import_results = session[:last_import_results]

    if import_results.nil?
      redirect_to people_path, alert: "No import results found."
      return
    end

    if import_results[:failed_people].blank?
      redirect_to people_path, alert: "No error data found to export."
      return
    end

    csv_content = generate_error_export_csv(import_results[:failed_people])

    respond_to do |format|
      format.csv do
        send_data csv_content,
                  filename: "person_import_errors_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                  type: "text/csv",
                  disposition: "attachment"
      end
    end
  end

  # GET /people/service_stats
  def service_stats
    respond_to do |format|
      format.turbo_stream do
        # Cache the stats for 1 second to ensure real-time updates
        stats_data = Rails.cache.fetch("person_service_stats_data", expires_in: 1.second) do
          calculate_service_stats
        end

        queue_stats = get_queue_stats

        render turbo_stream: [
          turbo_stream.replace("person_profile_extraction_stats",
            partial: "people/service_stats",
            locals: {
              service_name: "person_profile_extraction",
              service_title: "Profile Extraction",
              companies_needing: stats_data[:profile_needing],
              companies_potential: stats_data[:profile_potential],
              queue_depth: queue_stats["person_profile_extraction"] || 0
            }
          ),
          turbo_stream.replace("people_queue_statistics",
            partial: "people/queue_statistics",
            locals: { queue_stats: queue_stats }
          )
        ]
      end
    end
  end

  private

  def set_person
    @person = Person.find(params[:id])
  end

  def cleanup_old_import_results
    # Clean up result files older than 1 hour
    pattern = Rails.root.join("tmp", "person_import_result_*.json")
    Dir.glob(pattern).each do |file_path|
      if File.mtime(file_path) < 1.hour.ago
        File.delete(file_path)
        Rails.logger.debug "Cleaned up old import result file: #{File.basename(file_path)}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to cleanup old import result files: #{e.message}"
  end

  def calculate_service_stats
    {
      profile_needing: Company.needing_service("person_profile_extraction").count,
      profile_potential: Company.profile_extraction_potential.count,
      email_needing: Person.needing_email_extraction.count,
      social_media_needing: Person.needing_social_media_extraction.count
    }
  end

  def person_params
    params.require(:person).permit(
      :name, :profile_url, :title, :company_name, :location,
      :email, :phone, :connection_degree, :phantom_run_id,
      :company_id
    )
  end

  def generate_person_csv_template
    headers = [
      "Name",
      "First name",
      "Last name",
      "Email",
      "Email Status",
      "Title",
      "Linkedin",
      "Location",
      "Company Name",
      "Phone"
    ]

    sample_data = [
      [
        "John Doe",
        "John",
        "Doe",
        "john.doe@example.com",
        "Valid",
        "Software Engineer",
        "https://linkedin.com/in/johndoe",
        "San Francisco, CA",
        "Example Corp",
        "+1-555-123-4567"
      ],
      [
        "Jane Smith",
        "Jane",
        "Smith",
        "jane.smith@testcorp.com",
        "Valid",
        "Product Manager",
        "https://linkedin.com/in/janesmith",
        "New York, NY",
        "Test Corporation",
        "+1-555-987-6543"
      ]
    ]

    CSV.generate do |csv|
      csv << headers
      sample_data.each { |row| csv << row }
    end
  end

  def generate_error_export_csv(failed_people)
    headers = [ "Row", "Name", "Email", "Company", "Errors" ]

    CSV.generate do |csv|
      csv << headers
      failed_people.each do |failed_person|
        csv << [
          failed_person["row"],
          failed_person["name"],
          failed_person["email"],
          failed_person["company_name"],
          failed_person["errors"].join("; ")
        ]
      end
    end
  end

  # GET /people/export_with_validation.csv
  def export_with_validation
    import_tag = params[:import_tag]

    if import_tag.blank?
      redirect_to people_path, alert: "No import tag provided."
      return
    end

    # Find all people from this import
    people = Person.where(import_tag: import_tag).includes(:company)

    if people.empty?
      redirect_to people_path, alert: "No people found for this import."
      return
    end

    # Generate CSV with validation results
    respond_to do |format|
      format.csv do
        csv_data = generate_csv_with_validation(people)
        send_data csv_data,
                  filename: "people_import_with_validation_#{import_tag}_#{Date.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  end

  private

  def generate_csv_with_validation(people)
    CSV.generate(headers: true) do |csv|
      # CSV headers including validation fields
      csv << [
        "name",
        "email",
        "title",
        "company_name",
        "location",
        "linkedin",
        "phone",
        "email_verification_status",
        "email_verification_confidence",
        "email_verification_checked_at",
        "import_tag"
      ]

      people.each do |person|
        csv << [
          person.name,
          person.email,
          person.title,
          person.company_name,
          person.location,
          person.profile_url,
          person.phone,
          person.email_verification_status || "unverified",
          person.email_verification_confidence || 0.0,
          person.email_verification_checked_at&.strftime("%Y-%m-%d %H:%M:%S"),
          person.import_tag
        ]
      end
    end
  end

  def get_queue_stats
    require "sidekiq/api"

    stats = {}
    queue_names = [ "person_profile_extraction", "person_email_extraction", "person_social_media_extraction", "default" ]

    queue_names.each do |queue_name|
      begin
        queue = Sidekiq::Queue.new(queue_name)
        stats[queue_name] = queue.size
      rescue => e
        stats[queue_name] = "Error: #{e.message}"
      end
    end

    # Get people-specific stats
    begin
      sidekiq_stats = Sidekiq::Stats.new

      # Count total people services processed from ServiceAuditLog
      # Note: person_profile_extraction operates on Companies (extracting their people)
      # while email/social extraction might operate on Person records
      people_services = [ "person_profile_extraction", "person_email_extraction", "person_social_media_extraction" ]

      stats[:total_processed] = ServiceAuditLog.where(
        service_name: people_services,
        status: ServiceAuditLog::STATUS_SUCCESS
      ).count

      stats[:total_failed] = sidekiq_stats.failed
      stats[:total_enqueued] = sidekiq_stats.enqueued
      stats[:workers_busy] = sidekiq_stats.workers_size
    rescue => e
      stats[:error] = "Unable to fetch stats: #{e.message}"
    end

    stats
  end
end
