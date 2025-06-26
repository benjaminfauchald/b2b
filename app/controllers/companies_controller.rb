# frozen_string_literal: true

class CompaniesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_company, only: %i[show edit update destroy queue_single_financial_data queue_single_web_discovery queue_single_linkedin_discovery queue_single_employee_discovery]
  skip_before_action :verify_authenticity_token, only: [ :queue_financial_data, :queue_web_discovery, :queue_linkedin_discovery, :queue_employee_discovery, :queue_single_financial_data, :queue_single_web_discovery, :queue_single_linkedin_discovery, :queue_single_employee_discovery ]

  def index
    companies_scope = Company.includes(:service_audit_logs)
                            .order(created_at: :desc)

    if params[:search].present?
      companies_scope = companies_scope.where(
        "company_name ILIKE :search OR registration_number ILIKE :search",
        search: "%#{params[:search]}%"
      )
    end

    if params[:filter] == "with_financials"
      companies_scope = companies_scope.with_financial_data
    elsif params[:filter] == "without_financials"
      companies_scope = companies_scope.without_financial_data
    elsif params[:filter] == "needs_update"
      companies_scope = companies_scope.needs_financial_update
    elsif params[:filter] == "with_web_discovery"
      companies_scope = companies_scope.with_web_discovery
    elsif params[:filter] == "without_web_discovery"
      companies_scope = companies_scope.without_web_discovery
    elsif params[:filter] == "needs_web_discovery"
      companies_scope = companies_scope.needing_web_discovery
    end

    @pagy, @companies = pagy(companies_scope)
    @queue_stats = get_queue_stats
  end

  def show
    @financial_data = @company.financial_data
    @service_audit_logs = @company.service_audit_logs
                                .order(created_at: :desc)
                                .limit(10)
  end

  def financial_data
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "company_financial_data_#{@company.id}",
          partial: "companies/financial_data_card",
          locals: { company: @company }
        )
      end
    end
  end

  def new
    @company = Company.new
  end

  def edit
  end

  def create
    @company = Company.new(company_params)

    if @company.save
      redirect_to @company, notice: "Company was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @company.update(company_params)
      redirect_to @company, notice: "Company was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @company.destroy!
    redirect_to companies_url, notice: "Company was successfully destroyed."
  end

  # POST /companies/queue_financial_data
  def queue_financial_data
    unless ServiceConfiguration.active?("company_financial_data")
      render json: { success: false, message: "Financial data service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 companies at once" }
      return
    end

    # Get available companies that need processing
    available_companies = Company.needing_service("company_financial_data")
    available_count = available_companies.count

    # Check if we have enough companies to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No companies need financial data processing at this time",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} companies need financial data processing, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    companies = available_companies.limit(count)

    queued = 0
    companies.each do |company|
      CompanyFinancialDataWorker.perform_async(company.id)
      queued += 1
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("service_stats_data")

    render json: {
      success: true,
      message: "Queued #{queued} companies for financial data update",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /companies/queue_web_discovery
  def queue_web_discovery
    unless ServiceConfiguration.active?("company_web_discovery")
      render json: { success: false, message: "Web discovery service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 companies at once" }
      return
    end

    # Get available companies that need processing
    available_companies = Company.needing_service("company_web_discovery")
    available_count = available_companies.count

    # Check if we have enough companies to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No companies need web discovery processing at this time",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} companies need web discovery processing, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    companies = available_companies.limit(count)

    queued = 0
    companies.each do |company|
      CompanyWebDiscoveryWorker.perform_async(company.id)
      queued += 1
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("service_stats_data")

    render json: {
      success: true,
      message: "Queued #{queued} companies for web discovery",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /companies/queue_linkedin_discovery
  def queue_linkedin_discovery
    unless ServiceConfiguration.active?("company_linkedin_discovery")
      render json: { success: false, message: "LinkedIn discovery service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 companies at once" }
      return
    end

    # Get available companies that need processing
    available_companies = Company.needing_service("company_linkedin_discovery")
    available_count = available_companies.count

    # Check if we have enough companies to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No companies need LinkedIn discovery processing at this time",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} companies need LinkedIn discovery processing, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    companies = available_companies.limit(count)

    queued = 0
    companies.each do |company|
      CompanyLinkedinDiscoveryWorker.perform_async(company.id)
      queued += 1
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("service_stats_data")

    render json: {
      success: true,
      message: "Queued #{queued} companies for LinkedIn discovery",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # POST /companies/queue_employee_discovery
  def queue_employee_discovery
    unless ServiceConfiguration.active?("company_employee_discovery")
      render json: { success: false, message: "Employee discovery service is disabled" }
      return
    end

    count = params[:count]&.to_i || 10

    # Validate count is positive and reasonable
    if count <= 0
      render json: { success: false, message: "Count must be greater than 0" }
      return
    end

    if count > 1000
      render json: { success: false, message: "Cannot queue more than 1000 companies at once" }
      return
    end

    # Get available companies that need processing
    available_companies = Company.needing_service("company_employee_discovery")
    available_count = available_companies.count

    # Check if we have enough companies to queue
    if available_count == 0
      render json: {
        success: false,
        message: "No companies need employee discovery processing at this time",
        available_count: 0
      }
      return
    end

    if count > available_count
      render json: {
        success: false,
        message: "Only #{available_count} companies need employee discovery processing, but #{count} were requested",
        available_count: available_count
      }
      return
    end

    companies = available_companies.limit(count)

    queued = 0
    companies.each do |company|
      CompanyEmployeeDiscoveryWorker.perform_async(company.id)
      queued += 1
    end

    render json: {
      success: true,
      message: "Queued #{queued} companies for employee discovery",
      queued_count: queued,
      available_count: available_count,
      queue_stats: get_queue_stats
    }
  end

  # GET /companies/enhancement_queue_status
  def enhancement_queue_status
    render json: {
      success: true,
      queue_stats: get_queue_stats
    }
  end

  # GET /companies/service_stats
  def service_stats
    respond_to do |format|
      format.turbo_stream do
        # Cache the stats for 1 second to ensure real-time updates
        stats_data = Rails.cache.fetch("service_stats_data", expires_in: 1.second) do
          calculate_service_stats
        end
        
        queue_stats = get_queue_stats
        
        render turbo_stream: [
          turbo_stream.replace("company_financial_data_stats",
            partial: "companies/service_stats",
            locals: {
              service_name: "company_financial_data",
              companies_needing: stats_data[:financial_needing],
              queue_depth: queue_stats["company_financial_data"] || 0
            }
          ),
          turbo_stream.replace("company_web_discovery_stats",
            partial: "companies/service_stats",
            locals: {
              service_name: "company_web_discovery",
              companies_needing: stats_data[:web_discovery_needing],
              companies_potential: stats_data[:web_discovery_potential],
              queue_depth: queue_stats["company_web_discovery"] || 0
            }
          ),
          turbo_stream.replace("company_linkedin_discovery_stats",
            partial: "companies/service_stats",
            locals: {
              service_name: "company_linkedin_discovery",
              companies_needing: stats_data[:linkedin_needing],
              queue_depth: queue_stats["company_linkedin_discovery"] || 0
            }
          ),
          turbo_stream.replace("queue_statistics",
            partial: "companies/queue_statistics",
            locals: { queue_stats: queue_stats }
          )
        ]
      end
    end
  end

  # POST /companies/:id/queue_single_financial_data
  def queue_single_financial_data
    unless ServiceConfiguration.active?("company_financial_data")
      render json: { success: false, message: "Financial data service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "company_financial_data",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: [ "revenue", "profit" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = CompanyFinancialDataWorker.perform_async(@company.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("service_stats_data")

      render json: {
        success: true,
        message: "Company queued for financial data update",
        company_id: @company.id,
        service: "financial_data",
        job_id: job_id,
        worker: "CompanyFinancialDataWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue company for financial data update: #{e.message}"
      }
    end
  end

  # POST /companies/:id/queue_single_web_discovery
  def queue_single_web_discovery
    unless ServiceConfiguration.active?("company_web_discovery")
      render json: { success: false, message: "Web discovery service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "company_web_discovery",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: [ "web_pages" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = CompanyWebDiscoveryWorker.perform_async(@company.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("service_stats_data")

      render json: {
        success: true,
        message: "Company queued for web discovery",
        company_id: @company.id,
        service: "web_discovery",
        job_id: job_id,
        worker: "CompanyWebDiscoveryWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue company for web discovery: #{e.message}"
      }
    end
  end

  # POST /companies/:id/queue_single_linkedin_discovery
  def queue_single_linkedin_discovery
    unless ServiceConfiguration.active?("company_linkedin_discovery")
      render json: { success: false, message: "LinkedIn discovery service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "company_linkedin_discovery",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: [ "linkedin_url" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = CompanyLinkedinDiscoveryWorker.perform_async(@company.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("service_stats_data")

      render json: {
        success: true,
        message: "Company queued for LinkedIn discovery",
        company_id: @company.id,
        service: "linkedin_discovery",
        job_id: job_id,
        worker: "CompanyLinkedinDiscoveryWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue company for LinkedIn discovery: #{e.message}"
      }
    end
  end

  # POST /companies/:id/queue_single_employee_discovery
  def queue_single_employee_discovery
    unless ServiceConfiguration.active?("company_employee_discovery")
      render json: { success: false, message: "Employee discovery service is disabled" }
      return
    end

    begin
      # Create service audit log for queueing action
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "company_employee_discovery",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: [ "employees_data" ],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          timestamp: Time.current
        }
      )

      job_id = CompanyEmployeeDiscoveryWorker.perform_async(@company.id)

      # Invalidate cache immediately when queue changes
      Rails.cache.delete("service_stats_data")

      render json: {
        success: true,
        message: "Company queued for employee discovery",
        company_id: @company.id,
        service: "employee_discovery",
        job_id: job_id,
        worker: "CompanyEmployeeDiscoveryWorker",
        audit_log_id: audit_log.id
      }
    rescue => e
      render json: {
        success: false,
        message: "Failed to queue company for employee discovery: #{e.message}"
      }
    end
  end

  private

  def set_company
    @company = Company.find(params[:id])
  end

  def calculate_service_stats
    {
      financial_needing: Company.needing_service("company_financial_data").count,
      web_discovery_needing: Company.needing_service("company_web_discovery").count,
      web_discovery_potential: Company.web_discovery_potential.count,
      linkedin_needing: Company.needing_service("company_linkedin_discovery").count
    }
  end

  def company_params
    params.require(:company).permit(
      :registration_number, :company_name, :organization_form_code,
      :organization_form_description, :source_country, :source_registry,
      :website, :email, :phone, :mobile,
      :postal_address, :postal_code, :postal_city, :postal_municipality,
      :postal_municipality_no, :postal_country_code,
      :business_address, :business_code, :business_city, :business_municipality,
      :business_municipality_no, :business_country_code,
      :industry_code_1, :industry_code_1_description,
      :industry_code_2, :industry_code_2_description,
      :industry_code_3, :industry_code_3_description,
      :employees, :founding_date, :registration_date, :update_date,
      :vat_registered, :under_liquidation, :under_deletion, :bankruptcy
    )
  end

  def get_queue_stats
    require "sidekiq/api"

    stats = {}
    queue_names = [ "company_financial_data", "company_web_discovery", "company_linkedin_discovery", "company_employee_discovery", "default" ]

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
end
