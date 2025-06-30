require "ostruct"
require "csv"

class DomainsController < ApplicationController
  before_action :set_domain, only: %i[ show edit update destroy queue_single_dns queue_single_mx queue_single_www queue_single_web_content ]
  skip_before_action :verify_authenticity_token, only: [ :queue_testing, :queue_dns_testing, :queue_mx_testing, :queue_a_record_testing, :queue_web_content_extraction, :queue_single_dns, :queue_single_mx, :queue_single_www, :queue_single_web_content ]

  # GET /domains or /domains.json
  def index
    domains = apply_successful_services_filter(Domain.all)
    @pagy, @domains = pagy(domains.order(created_at: :desc))
    @queue_stats = get_queue_stats
  end

  # GET /domains/1 or /domains/1.json
  def show
  end

  # GET /domains/new
  def new
    @domain = Domain.new
  end

  # GET /domains/1/edit
  def edit
  end

  # POST /domains or /domains.json
  def create
    @domain = Domain.new(domain_params)

    respond_to do |format|
      if @domain.save
        format.html { redirect_to @domain, notice: "Domain was successfully created." }
        format.json { render :show, status: :created, location: @domain }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @domain.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /domains/1 or /domains/1.json
  def update
    respond_to do |format|
      if @domain.update(domain_params)
        format.html { redirect_to @domain, notice: "Domain was successfully updated." }
        format.json { render :show, status: :ok, location: @domain }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @domain.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /domains/1 or /domains/1.json
  def destroy
    @domain.destroy!

    respond_to do |format|
      format.html { redirect_to domains_path, status: :see_other, notice: "Domain was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  # POST /domains/queue_testing
  def queue_testing
    count = params[:count].to_i

    if count <= 0 || count > 1000
      render json: {
        success: false,
        message: "Please enter a number between 1 and 1000"
      }, status: :unprocessable_entity
      return
    end

    begin
      # Use the existing rake task logic to queue domains
      domains_to_test = Domain.limit(count)

      if domains_to_test.empty?
        render json: {
          success: false,
          message: "No domains available for testing"
        }, status: :unprocessable_entity
        return
      end

      queued_count = 0
      domains_to_test.each do |domain|
        DomainDnsTestingWorker.perform_async(domain.id)
        queued_count += 1
      end

      render json: {
        success: true,
        message: "Successfully queued #{queued_count} domains for DNS testing",
        queued_count: queued_count,
        queue_stats: get_queue_stats
      }

    rescue => e
      render json: {
        success: false,
        message: "Error queueing domains: #{e.message}"
      }, status: :internal_server_error
    end
  end

  # POST /domains/queue_dns_testing
  def queue_dns_testing
    unless ServiceConfiguration.active?("domain_testing")
      render json: { success: false, message: "DNS testing service is disabled" }
      return
    end

    count = params[:count]&.to_i || 100

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 domains at once" }
      return
    end

    # Get available domains that need testing
    available_domains = Domain.needing_service("domain_testing")
    available_count = available_domains.count

    # Check if we have any domains to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No domains need DNS testing at this time",
        available_count: 0
      }
      return
    end

    # Adjust count to available domains if necessary
    actual_count = [ count, available_count ].min

    # Queue up to the requested number of domains (or all available if less)
    domains = available_domains.limit(actual_count)
    queued = 0

    domains.each do |domain|
      DomainDnsTestingWorker.perform_async(domain.id)
      queued += 1
    end

    render json: {
      success: true,
      message: actual_count < count ?
        "Queued all #{queued} available domains for DNS testing (requested: #{count})" :
        "Queued #{queued} domains for DNS testing",
      queued_count: queued,
      requested_count: count,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /domains/queue_mx_testing
  def queue_mx_testing
    unless ServiceConfiguration.active?("domain_mx_testing")
      render json: { success: false, message: "MX testing service is disabled" }
      return
    end

    count = params[:count]&.to_i || 100

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 domains at once" }
      return
    end

    # Get available domains that need testing
    available_domains = Domain.needing_service("domain_mx_testing")
    available_count = available_domains.count

    # Check if we have any domains to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No domains need MX testing at this time",
        available_count: 0
      }
      return
    end

    # Adjust count to available domains if necessary
    actual_count = [ count, available_count ].min

    # Queue up to the requested number of domains (or all available if less)
    domains = available_domains.limit(actual_count)
    queued = 0

    domains.each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      queued += 1
    end

    render json: {
      success: true,
      message: actual_count < count ?
        "Queued all #{queued} available domains for MX testing (requested: #{count})" :
        "Queued #{queued} domains for MX testing",
      queued_count: queued,
      requested_count: count,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /domains/queue_a_record_testing
  def queue_a_record_testing
    unless ServiceConfiguration.active?("domain_a_record_testing")
      render json: { success: false, message: "A Record testing service is disabled" }
      return
    end

    count = params[:count]&.to_i || 100

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 domains at once" }
      return
    end

    # Get available domains that need testing (domains with active DNS but no WWW test)
    available_domains = Domain.dns_active.where(www: nil)
    available_count = available_domains.count

    # Check if we have any domains to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No domains need A Record testing at this time",
        available_count: 0
      }
      return
    end

    # Adjust count to available domains if necessary
    actual_count = [ count, available_count ].min

    # Queue up to the requested number of domains (or all available if less)
    domains = available_domains.limit(actual_count)
    queued = 0

    domains.each do |domain|
      DomainARecordTestingWorker.perform_async(domain.id)
      queued += 1
    end

    render json: {
      success: true,
      message: actual_count < count ?
        "Queued all #{queued} available domains for A Record testing (requested: #{count})" :
        "Queued #{queued} domains for A Record testing",
      queued_count: queued,
      requested_count: count,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /domains/queue_web_content_extraction
  def queue_web_content_extraction
    unless ServiceConfiguration.active?("domain_web_content_extraction")
      render json: {
        success: false,
        message: "Web content extraction service is disabled"
      }
      return
    end

    count = params[:count].to_i

    if count <= 0 || count > 1000
      render json: {
        success: false,
        message: "Please enter a number between 1 and 1000"
      }, status: :unprocessable_entity
      return
    end

    # Get domains that need web content extraction
    available_domains = Domain.needing_web_content
    available_count = available_domains.count

    # Check if we have any domains to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No domains need web content extraction at this time",
        available_count: 0
      }
      return
    end

    # Adjust count to available domains if necessary
    actual_count = [ count, available_count ].min

    # Queue up to the requested number of domains (or all available if less)
    domains = available_domains.limit(actual_count)
    queued = 0

    domains.each do |domain|
      DomainWebContentExtractionWorker.perform_async(domain.id)
      queued += 1
    end

    render json: {
      success: true,
      message: actual_count < count ?
        "Queued all #{queued} available domains for web content extraction (requested: #{count})" :
        "Queued #{queued} domains for web content extraction",
      queued_count: queued,
      requested_count: count,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # GET /domains/queue_status
  def queue_status
    render json: {
      success: true,
      queue_stats: get_queue_stats
    }
  end

  # POST /domains/:id/queue_single_dns
  def queue_single_dns
    unless ServiceConfiguration.active?("domain_testing")
      render json: { success: false, message: "DNS testing service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @domain,
        service_name: "domain_testing",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @domain.class.table_name,
        record_id: @domain.id.to_s,
        columns_affected: [ "dns" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = DomainDnsTestingWorker.perform_async(@domain.id)

      render json: {
        success: true,
        message: "Domain queued for DNS testing",
        domain_id: @domain.id,
        service: "dns",
        job_id: job_id,
        worker: "DomainDnsTestingWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue domain for DNS testing: #{e.message}"
      }
    end
  end

  # POST /domains/:id/queue_single_mx
  def queue_single_mx
    unless ServiceConfiguration.active?("domain_mx_testing")
      render json: { success: false, message: "MX testing service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @domain,
        service_name: "domain_mx_testing",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @domain.class.table_name,
        record_id: @domain.id.to_s,
        columns_affected: [ "mx" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = DomainMxTestingWorker.perform_async(@domain.id)

      render json: {
        success: true,
        message: "Domain queued for MX testing",
        domain_id: @domain.id,
        service: "mx",
        job_id: job_id,
        worker: "DomainMxTestingWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue domain for MX testing: #{e.message}"
      }
    end
  end

  # POST /domains/:id/queue_single_www
  def queue_single_www
    unless ServiceConfiguration.active?("domain_a_record_testing")
      render json: { success: false, message: "WWW testing service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @domain,
        service_name: "domain_a_record_testing",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @domain.class.table_name,
        record_id: @domain.id.to_s,
        columns_affected: [ "www" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = DomainARecordTestingWorker.perform_async(@domain.id)

      render json: {
        success: true,
        message: "Domain queued for WWW testing",
        domain_id: @domain.id,
        service: "www",
        job_id: job_id,
        worker: "DomainARecordTestingWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue domain for WWW testing: #{e.message}"
      }
    end
  end

  # POST /domains/:id/queue_single_web_content
  def queue_single_web_content
    unless ServiceConfiguration.active?("domain_web_content_extraction")
      render json: { success: false, message: "Web content extraction service is disabled" }
      return
    end

    # Check if domain has prerequisites (A record)
    unless @domain.www && @domain.a_record_ip.present?
      render json: {
        success: false,
        message: "Domain must have a valid A record before web content extraction"
      }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @domain,
        service_name: "domain_web_content_extraction",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @domain.class.table_name,
        record_id: @domain.id.to_s,
        columns_affected: [ "web_content_data" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = DomainWebContentExtractionWorker.perform_async(@domain.id)

      render json: {
        success: true,
        message: "Domain queued for web content extraction",
        domain_id: @domain.id,
        service: "web_content",
        job_id: job_id,
        worker: "DomainWebContentExtractionWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue domain for web content extraction: #{e.message}"
      }
    end
  end

  # GET /domains/import
  def import_csv
    # Show the CSV import form
  end

  # POST /domains/import
  def process_import
    request_start_time = Time.current
    Rails.logger.info "\n" + "="*60
    Rails.logger.info "🚀 CSV IMPORT REQUEST START: #{request_start_time}"
    Rails.logger.info "="*60

    Rails.logger.info "📋 REQUEST DETAILS:"
    Rails.logger.info "  - User ID: #{current_user&.id}"
    Rails.logger.info "  - User email: #{current_user&.email}"
    Rails.logger.info "  - Request IP: #{request.remote_ip}"
    Rails.logger.info "  - User agent: #{request.user_agent&.truncate(100)}"
    Rails.logger.info "  - Params present: #{params.keys}"
    Rails.logger.info "  - CSV file present: #{params[:csv_file].present?}"

    if params[:csv_file]
      Rails.logger.info "📁 FILE DETAILS:"
      Rails.logger.info "  - File class: #{params[:csv_file].class}"
      Rails.logger.info "  - File size: #{params[:csv_file].respond_to?(:size) ? "#{params[:csv_file].size} bytes (#{(params[:csv_file].size / 1024.0 / 1024.0).round(2)} MB)" : 'N/A'}"
      Rails.logger.info "  - File name: #{params[:csv_file].respond_to?(:original_filename) ? params[:csv_file].original_filename : 'N/A'}"
      Rails.logger.info "  - Content type: #{params[:csv_file].respond_to?(:content_type) ? params[:csv_file].content_type : 'N/A'}"
      Rails.logger.info "  - Temp file path: #{params[:csv_file].respond_to?(:path) ? params[:csv_file].path : 'N/A'}"
    end

    unless params[:csv_file].present?
      redirect_to import_domains_path, alert: "Please select a CSV file to upload."
      return
    end

    # Check rate limiting (simple session-based approach)
    if session[:last_import_at] && session[:last_import_at] > 5.seconds.ago
      redirect_to import_domains_path, alert: "Please wait a moment before importing again."
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

        # Save file to temporary location
        original_filename = params[:csv_file].respond_to?(:original_filename) ? params[:csv_file].original_filename : "import_#{import_id}.csv"
        temp_file_path = Rails.root.join("tmp", "import_#{import_id}_#{original_filename}")
        File.open(temp_file_path, "wb") do |file|
          file.write(params[:csv_file].read)
        end
        Rails.logger.info "  - Temporary file saved: #{temp_file_path}"

        # Queue the background job
        DomainImportJob.perform_later(
          temp_file_path.to_s,
          current_user.id,
          original_filename,
          import_id
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

        redirect_to import_status_domains_path
        return
      else
        # Small file - process synchronously
        Rails.logger.info "\n🔧 SYNCHRONOUS PROCESSING:"

        # Service instantiation
        service_creation_start = Time.current
        Rails.logger.info "  - Creating service..."

        import_service = DomainImportService.new(
          file: params[:csv_file],
          user: current_user
        )

        service_creation_duration = Time.current - service_creation_start
        Rails.logger.info "  - Service created in #{service_creation_duration.round(6)} seconds"

        # Service execution
        service_execution_start = Time.current
        Rails.logger.info "  - Starting import execution..."

        result = import_service.perform
      end

      service_execution_duration = Time.current - service_execution_start
      Rails.logger.info "\n✅ SERVICE EXECUTION COMPLETE:"
      Rails.logger.info "  - Execution duration: #{service_execution_duration.round(4)} seconds"
      Rails.logger.info "  - Result class: #{result.class}"
      Rails.logger.info "  - Result success?: #{result.success?}"

      if result.respond_to?(:data) && result.data.is_a?(Hash)
        Rails.logger.info "  - Result data keys: #{result.data.keys}"
      end

      # Result processing
      result_processing_start = Time.current
      Rails.logger.info "\n📊 RESULT PROCESSING START:"

      # Handle both DomainImportResult and OpenStruct (error) results
      if result.success?
        Rails.logger.info "  - Processing successful result"
        import_data = result.data[:result] || result

        Rails.logger.info "  - Import data class: #{import_data.class}"
        Rails.logger.info "  - Imported count: #{import_data.imported_count || 0}"
        Rails.logger.info "  - Failed count: #{import_data.failed_count || 0}"
        Rails.logger.info "  - Duplicate count: #{import_data.duplicate_count || 0}"
        Rails.logger.info "  - Total count: #{import_data.total_count || 0}"
        Rails.logger.info "  - Processing time: #{import_data.processing_time}"

        session_data = {
          success: true,
          imported_count: import_data.imported_count || 0,
          failed_count: import_data.failed_count || 0,
          duplicate_count: import_data.duplicate_count || 0,
          total_count: import_data.total_count || 0,
          processing_time: import_data.processing_time,
          summary_message: import_data.summary_message || "Import completed",
          csv_errors: (import_data.csv_errors || []).first(3),
          failed_domains: (import_data.failed_domains || []).first(10),
          duplicate_domains: (import_data.duplicate_domains || []).first(10)
        }

        session[:import_results] = session_data.to_json
        Rails.logger.info "  - Session data size: #{session[:import_results].length} characters"

      else
        Rails.logger.info "  - Processing failed result"
        error_message = result.error || "Import failed"
        Rails.logger.info "  - Error message: #{error_message}"

        # Use actual data from service result even for error cases
        import_data = result.data[:result] || result
        
        Rails.logger.info "  - Import data class: #{import_data.class}"
        Rails.logger.info "  - Imported count: #{import_data.imported_count || result.data[:imported] || 0}"
        Rails.logger.info "  - Failed count: #{import_data.failed_count || result.data[:failed] || 0}"
        Rails.logger.info "  - Duplicate count: #{import_data.duplicate_count || result.data[:duplicates] || 0}"

        session_data = {
          success: false,
          imported_count: import_data.imported_count || result.data[:imported] || 0,
          failed_count: import_data.failed_count || result.data[:failed] || 0,
          duplicate_count: import_data.duplicate_count || result.data[:duplicates] || 0,
          total_count: (import_data.imported_count || result.data[:imported] || 0) + 
                      (import_data.failed_count || result.data[:failed] || 0) + 
                      (import_data.duplicate_count || result.data[:duplicates] || 0),
          processing_time: (import_data.processing_time rescue nil),
          summary_message: error_message,
          csv_errors: (import_data.csv_errors || []).first(3),
          failed_domains: (import_data.failed_domains || []).first(10),
          duplicate_domains: (import_data.duplicate_domains || []).first(10)
        }

        session[:import_results] = session_data.to_json
        Rails.logger.info "  - Session data size: #{session[:import_results].length} characters"
      end

      session[:last_import_at] = Time.current
      result_processing_duration = Time.current - result_processing_start

      total_request_duration = Time.current - request_start_time
      Rails.logger.info "\n📈 FINAL REQUEST SUMMARY:"
      Rails.logger.info "  - Result processing: #{result_processing_duration.round(4)} seconds"
      Rails.logger.info "  - Total request time: #{total_request_duration.round(4)} seconds"
      Rails.logger.info "  - About to redirect to import_results_domains_path"

      redirect_to import_results_domains_path

    rescue StandardError => e
      error_time = Time.current
      error_duration = error_time - request_start_time

      Rails.logger.error "\n" + "🚨" * 20
      Rails.logger.error "❌ IMPORT FAILED AFTER #{error_duration.round(4)} SECONDS"
      Rails.logger.error "🚨" * 20
      Rails.logger.error "⏰ Error occurred at: #{error_time}"
      Rails.logger.error "🔥 Error class: #{e.class}"
      Rails.logger.error "💥 Error message: #{e.message}"
      Rails.logger.error "📍 Error location: #{e.backtrace.first}"
      Rails.logger.error "\n📚 Full backtrace:"
      Rails.logger.error e.backtrace.join("\n")
      Rails.logger.error "\n🔍 Additional context:"
      Rails.logger.error "  - User: #{current_user&.email}"
      Rails.logger.error "  - File size: #{params[:csv_file]&.size} bytes"
      Rails.logger.error "  - File name: #{params[:csv_file]&.respond_to?(:original_filename) ? params[:csv_file].original_filename : 'N/A'}"
      Rails.logger.error "  - Request duration: #{error_duration.round(4)} seconds"
      Rails.logger.error "🚨" * 20

      redirect_to import_domains_path, alert: "Import failed: #{e.message}"
    end
  end

  # GET /domains/import_results
  def import_results
    unless session[:import_results]
      redirect_to import_domains_path, alert: "No import results found. Please import a CSV file first."
      return
    end

    begin
      @import_result = JSON.parse(session[:import_results], object_class: OpenStruct)
      session.delete(:import_results) # Clear after displaying
    rescue JSON::ParserError
      redirect_to import_domains_path, alert: "Invalid import results. Please try importing again."
    end
  end

  # GET /domains/import_status
  def import_status
    unless session[:import_id]
      redirect_to import_domains_path, alert: "No import in progress."
      return
    end

    @import_id = session[:import_id]
    @import_started_at = session[:import_started_at]
  end

  # GET /domains/check_import_status (AJAX)
  def check_import_status
    import_id = session[:import_id]

    unless import_id
      render json: { status: "no_import", message: "No import in progress" }
      return
    end

    # Check cache for status
    status_data = Rails.cache.read("import_status_#{import_id}")
    result_data = Rails.cache.read("import_result_#{import_id}")

    if result_data
      # Import completed
      if result_data[:success]
        # Store result in session for display
        session[:import_results] = {
          success: true,
          imported_count: result_data[:result].data[:imported] || 0,
          failed_count: result_data[:result].data[:failed] || 0,
          duplicate_count: result_data[:result].data[:duplicates] || 0,
          total_count: result_data[:result].data[:imported] + result_data[:result].data[:failed] + result_data[:result].data[:duplicates],
          processing_time: (result_data[:completed_at] - Time.parse(session[:import_started_at].to_s)).round(2),
          summary_message: "Background import completed successfully"
        }.to_json

        # Clean up session
        session.delete(:import_id)
        session.delete(:import_status)
        session.delete(:import_started_at)

        render json: {
          status: "completed",
          success: true,
          redirect_url: import_results_domains_path
        }
      else
        # Import failed
        session[:import_results] = {
          success: false,
          imported_count: 0,
          failed_count: 0,
          duplicate_count: 0,
          total_count: 0,
          processing_time: nil,
          summary_message: result_data[:error] || "Import failed",
          csv_errors: [ result_data[:error] || "Import failed" ]
        }.to_json

        # Clean up session
        session.delete(:import_id)
        session.delete(:import_status)
        session.delete(:import_started_at)

        render json: {
          status: "failed",
          success: false,
          error: result_data[:error],
          redirect_url: import_results_domains_path
        }
      end
    elsif status_data
      # Import in progress - return progress data
      response_data = {
        status: "processing",
        message: status_data[:message] || "Import in progress...",
        started_at: status_data[:started_at]
      }

      # Add progress information if available
      if status_data[:progress]
        response_data[:progress] = status_data[:progress]
      end

      render json: response_data
    else
      # Status not found - might be queued
      render json: {
        status: "queued",
        message: "Import queued for processing..."
      }
    end
  end

  # GET /domains/template
  def download_template
    csv_content = generate_csv_template

    send_data csv_content,
              filename: "domain_import_template.csv",
              type: "text/csv",
              disposition: "attachment"
  end

  # GET /domains/export_errors
  def export_errors
    # Get import results from session
    unless session[:import_results]
      redirect_to import_domains_path, alert: "No import errors found. Please import a CSV file first."
      return
    end

    begin
      import_result = JSON.parse(session[:import_results], object_class: OpenStruct)

      # Generate CSV with actual error data
      csv_content = CSV.generate(headers: true) do |csv|
        csv << [ "Row", "Domain", "Errors" ]

        # Add failed domains
        if import_result.failed_domains.present?
          import_result.failed_domains.each do |failed_domain|
            csv << [
              failed_domain["row"] || failed_domain[:row],
              failed_domain["domain"] || failed_domain[:domain] || "(blank)",
              Array(failed_domain["errors"] || failed_domain[:errors]).join("; ")
            ]
          end
        end

        # Add duplicate domains if any
        if import_result.duplicate_domains.present?
          import_result.duplicate_domains.each do |dup_domain|
            csv << [
              dup_domain["row"] || dup_domain[:row],
              dup_domain["domain"] || dup_domain[:domain],
              "Domain already exists (duplicate)"
            ]
          end
        end
      end

      send_data csv_content,
                filename: "import_errors_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: "text/csv",
                disposition: "attachment"
    rescue JSON::ParserError
      redirect_to import_domains_path, alert: "Error generating report. Please try importing again."
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_domain
      @domain = Domain.find(params.expect(:id))
    rescue ActiveRecord::RecordNotFound
      if request.format.json? || action_name.start_with?("queue_single_")
        render json: { success: false, message: "Domain not found" }, status: :not_found
      else
        redirect_to domains_path, alert: "Domain not found"
      end
    end

    # Only allow a list of trusted parameters through.
    def domain_params
      params.expect(domain: [ :domain, :www, :mx, :dns ])
    end

    def get_queue_stats
      require "sidekiq/api"

      stats = {}
      queue_names = [ "domain_dns_testing", "domain_mx_testing", "default" ]

      queue_names.each do |queue_name|
        begin
          queue = Sidekiq::Queue.new(queue_name)
          stats[queue_name] = queue.size
        rescue => e
          stats[queue_name] = "Error: #{e.message}"
        end
      end

      # Get worker-specific counts from the default queue
      begin
        default_queue = Sidekiq::Queue.new("default")

        # Count A Record Testing workers
        a_record_count = default_queue.count { |job| job.klass == "DomainARecordTestingWorker" }
        stats["DomainARecordTestingService"] = a_record_count

        # Count Web Content Extraction workers
        web_content_count = default_queue.count { |job| job.klass == "DomainWebContentExtractionWorker" }
        stats["DomainWebContentExtractionWorker"] = web_content_count
      rescue => e
        stats["DomainARecordTestingService"] = "Error: #{e.message}"
        stats["DomainWebContentExtractionWorker"] = "Error: #{e.message}"
      end

      # Get overall Sidekiq stats
      begin
        sidekiq_stats = Sidekiq::Stats.new
        stats[:total_processed] = sidekiq_stats.processed
        stats[:total_failed] = sidekiq_stats.failed
        stats[:total_enqueued] = sidekiq_stats.enqueued
        stats[:workers_busy] = sidekiq_stats.workers_size
      rescue => e
        stats[:error] = "Unable to fetch stats: #{e.message}"
      end

      # Get domains needing service counts for real-time updates
      stats[:domains_needing] = {
        domain_testing: Domain.needing_service("domain_testing").count,
        domain_mx_testing: Domain.needing_service("domain_mx_testing").count,
        domain_a_record_testing: Domain.needing_service("domain_a_record_testing").count,
        domain_web_content_extraction: Domain.needing_service("domain_web_content_extraction").count
      }

      stats
    end

    def public_action?
      %w[index queue_testing queue_status check_import_status].include?(action_name)
    end

    def generate_csv_template
      <<~CSV
        domain,dns,www,mx
        example.com,true,true,false
        sample.org,false,false,true
        test-domain.net,,true,
      CSV
    end


    def apply_successful_services_filter(domains)
      return domains unless params[:successful_services].present?

      case params[:successful_services]
      when "with_dns"
        domains.dns_active
      when "with_mx"
        domains.mx_active
      when "with_www"
        domains.www_active
      when "with_web_content"
        domains.web_content_extracted
      when "fully_tested"
        domains.dns_active.mx_tested.www_tested.where.not(web_content_data: nil)
      else
        domains
      end
    end

    def filter_params
      params.permit(:successful_services)
    end
end
