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
    Rails.logger.info "=== CSV UPLOAD DEBUG ==="
    Rails.logger.info "Params present: #{params.keys}"
    Rails.logger.info "CSV file present: #{params[:csv_file].present?}"
    Rails.logger.info "CSV file class: #{params[:csv_file].class}" if params[:csv_file]
    Rails.logger.info "CSV file size: #{params[:csv_file].size}" if params[:csv_file]
    Rails.logger.info "CSV file name: #{params[:csv_file].original_filename}" if params[:csv_file]
    Rails.logger.info "========================="
    
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
      puts "\n=== CONTROLLER: Starting CSV import ==="
      puts "File name: #{params[:csv_file].original_filename}"
      puts "File size: #{params[:csv_file].size}"

      import_service = DomainImportService.new(
        file: params[:csv_file],
        user: current_user
      )

      result = import_service.perform

      puts "Import result: #{result.inspect}"
      puts "Import result success?: #{result.success?}"
      puts "Import result class: #{result.class}"

      # Handle both DomainImportResult and OpenStruct (error) results
      if result.success?
        # Successful import with DomainImportResult
        import_data = result.data[:result] || result
        session[:import_results] = {
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
        }.to_json
      else
        # Failed import with error result
        error_message = result.error || "Import failed"
        session[:import_results] = {
          success: false,
          imported_count: 0,
          failed_count: 0,
          duplicate_count: 0,
          total_count: 0,
          processing_time: nil,
          summary_message: error_message,
          csv_errors: [error_message],
          failed_domains: [],
          duplicate_domains: []
        }.to_json
      end
      session[:last_import_at] = Time.current

      redirect_to import_results_domains_path

    rescue StandardError => e
      Rails.logger.error "Import failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
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

      stats
    end

    def public_action?
      %w[index queue_testing queue_status].include?(action_name)
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
      when 'with_dns'
        domains.dns_active
      when 'with_mx'
        domains.mx_active
      when 'with_www'
        domains.www_active
      when 'with_web_content'
        domains.web_content_extracted
      when 'fully_tested'
        domains.dns_active.mx_tested.www_tested.where.not(web_content_data: nil)
      else
        domains
      end
    end

    def filter_params
      params.permit(:successful_services)
    end
end
