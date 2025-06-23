class DomainsController < ApplicationController
  before_action :set_domain, only: %i[ show edit update destroy ]
  skip_before_action :verify_authenticity_token, only: [ :queue_testing ]

  # GET /domains or /domains.json
  def index
    @domains = Domain.all
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

  # GET /domains/queue_status
  def queue_status
    render json: {
      success: true,
      queue_stats: get_queue_stats
    }
  end

  # GET /domains/import
  def import_csv
    # Show the CSV import form
  end

  # POST /domains/import
  def process_import
    unless params[:csv_file].present?
      redirect_to import_domains_path, alert: "Please select a CSV file to upload."
      return
    end

    # Check rate limiting (simple session-based approach)
    if session[:last_import_at] && session[:last_import_at] > 30.seconds.ago
      redirect_to import_domains_path, alert: "Please wait before importing again."
      return
    end

    begin
      import_service = DomainImportService.new(
        file: params[:csv_file],
        user: current_user
      )

      result = import_service.perform

      # Store results in session for display
      session[:import_results] = result.to_json
      session[:last_import_at] = Time.current

      redirect_to import_results_domains_path

    rescue StandardError => e
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
    # This would typically get error data from session or database
    # For now, return a simple error template
    csv_content = "row,domain,errors\n2,invalid.domain,\"Domain format is invalid\"\n3,,\"Domain can't be blank\""

    send_data csv_content,
              filename: "import_errors_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
              type: "text/csv",
              disposition: "attachment"
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_domain
      @domain = Domain.find(params.expect(:id))
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
end
