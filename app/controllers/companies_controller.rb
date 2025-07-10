# frozen_string_literal: true

class CompaniesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_selected_country
  before_action :set_company, only: %i[show edit update destroy queue_single_financial_data queue_single_web_discovery queue_single_linkedin_discovery queue_single_employee_discovery profile_extraction_status linkedin_profiles]
  skip_before_action :verify_authenticity_token, only: [ :queue_financial_data, :queue_web_discovery, :queue_linkedin_discovery, :queue_employee_discovery, :queue_single_financial_data, :queue_single_web_discovery, :queue_single_linkedin_discovery, :queue_single_employee_discovery, :set_country ]

  def index
    companies_scope = Company.by_country(@selected_country)
                            .includes(:service_audit_logs)

    if params[:search].present?
      companies_scope = companies_scope.where(
        "company_name ILIKE :search OR registration_number ILIKE :search",
        search: "%#{params[:search]}%"
      )
    end

    if params[:filter] == "with_financials"
      companies_scope = companies_scope.with_financial_data
    elsif params[:filter] == "with_website"
      companies_scope = companies_scope.where.not(website: [ nil, "" ])
      # Order by revenue descending for with_website filter
      companies_scope = companies_scope.order(Arel.sql("COALESCE(operating_revenue, 0) DESC"))
    elsif params[:filter] == "with_linkedin"
      companies_scope = companies_scope.where.not(linkedin_url: [ nil, "" ]).or(companies_scope.where.not(linkedin_ai_url: [ nil, "" ]))
    else
      # Default order by created_at desc
      companies_scope = companies_scope.order(created_at: :desc)
    end

    @pagy, @companies = pagy(companies_scope)
    @queue_stats = get_queue_stats
    @available_countries = Company.distinct.pluck(:source_country).compact.sort
  end

  def show
    @financial_data = @company.financial_data
    @service_audit_logs = @company.service_audit_logs
                                .order(created_at: :desc)
                                .limit(10)
    @people = @company.people.order(created_at: :desc)
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

  def profile_extraction_status
    # Check if there's a pending or recently completed profile extraction
    recent_log = @company.service_audit_logs
                         .where(service_name: "person_profile_extraction")
                         .where("created_at > ?", 5.minutes.ago)
                         .order(created_at: :desc)
                         .first

    has_pending = recent_log && recent_log.status == "pending"
    recently_completed = recent_log && recent_log.status == "success" && recent_log.completed_at > 30.seconds.ago

    render json: {
      has_pending: has_pending,
      recently_completed: recently_completed,
      status: recent_log&.status,
      created_at: recent_log&.created_at
    }
  end

  def linkedin_profiles
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "company_linkedin_profiles_#{@company.id}",
          CompanyLinkedinProfilesComponent.new(company: @company)
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
    # Check if this is an inline edit (AJAX request)
    if request.xhr? || request.format.json?
      # Handle inline editing with audit logging
      allowed_fields = %w[website linkedin_url linkedin_ai_url email phone]
      field_to_update = company_params.keys.first.to_s

      if allowed_fields.include?(field_to_update)
        old_value = @company.send(field_to_update)
        new_value = company_params[field_to_update]

        if @company.update(company_params)
          # Log the user update to ServiceAuditLog
          ServiceAuditLog.create!(
            auditable: @company,
            service_name: "user_update",
            status: :success,
            started_at: Time.current,
            completed_at: Time.current,
            table_name: "companies",
            record_id: @company.id.to_s,
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

          # Handle domain creation/update if website was changed
          if field_to_update == "website" && new_value.present?
            domain_service = CompanyDomainService.new(@company, new_value)
            domain_result = domain_service.execute

            unless domain_result.success?
              Rails.logger.error "Failed to process domain: #{domain_result.error_message}"
            end
          end

          render json: { success: true, message: "Field updated successfully" }
        else
          render json: { success: false, error: @company.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      else
        render json: { success: false, error: "Field not allowed for inline editing" }, status: :forbidden
      end
    else
      # Regular form update - log all changed fields
      changed_fields = []
      allowed_fields = %w[website linkedin_url email phone]
      changes_metadata = {}

      allowed_fields.each do |field|
        if company_params.key?(field)
          old_value = @company.send(field)
          new_value = company_params[field]

          # Normalize nil and empty string for comparison
          normalized_old = old_value.presence
          normalized_new = new_value.presence

          if normalized_old != normalized_new
            changed_fields << field
            changes_metadata[field] = {
              old_value: old_value,
              new_value: new_value
            }
          end
        end
      end

      if @company.update(company_params)
        # Log user updates if any allowed fields were changed
        if changed_fields.any?
          ServiceAuditLog.create!(
            auditable: @company,
            service_name: "user_update",
            status: :success,
            started_at: Time.current,
            completed_at: Time.current,
            table_name: "companies",
            record_id: @company.id.to_s,
            operation_type: "update",
            columns_affected: changed_fields,
            execution_time_ms: 0,
            metadata: {
              fields_changed: changed_fields,
              changes: changes_metadata,
              updated_by: current_user.email,
              updated_at: Time.current.iso8601
            }
          )
        end

        # Handle domain creation/update if website was changed
        if changed_fields.include?("website") && company_params["website"].present?
          domain_service = CompanyDomainService.new(@company, company_params["website"])
          domain_result = domain_service.execute

          unless domain_result.success?
            Rails.logger.error "Failed to process domain: #{domain_result.error_message}"
          end
        end

        respond_to do |format|
          format.html { redirect_to @company, notice: "Company was successfully updated." }
          format.json { render json: { success: true, company: @company.as_json } }
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: { success: false, errors: @company.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end
  end

  def destroy
    @company.destroy!
    redirect_to companies_url, notice: "Company was successfully destroyed."
  end

  # POST /companies/queue_financial_data
  def queue_financial_data
    Rails.logger.info "========== queue_financial_data called =========="
    Rails.logger.info "Params: #{params.inspect}"

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
    available_companies = Company.by_country(@selected_country).needing_service("company_financial_data")
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
    Rails.logger.info "========== queue_web_discovery called =========="
    Rails.logger.info "Params: #{params.inspect}"

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
    available_companies = Company.by_country(@selected_country).needing_service("company_web_discovery")
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
    Rails.logger.info "========== queue_linkedin_discovery called =========="
    Rails.logger.info "Params: #{params.inspect}"

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
    available_companies = Company.by_country(@selected_country).needing_service("company_linkedin_discovery")
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

  # POST /companies/queue_linkedin_discovery_by_postal_code
  def queue_linkedin_discovery_by_postal_code
    # Write to a file to ensure logging works
    File.open(Rails.root.join('tmp', 'postal_code_debug.log'), 'a') do |f|
      f.puts "========== queue_linkedin_discovery_by_postal_code called at #{Time.now} =========="
      f.puts "Params: #{params.inspect}"
      f.puts "Request format: #{request.format}"
      f.puts "Request headers: #{request.headers['Accept']}"
    end
    
    Rails.logger.info "========== queue_linkedin_discovery_by_postal_code called =========="
    Rails.logger.info "Params: #{params.inspect}"
    Rails.logger.info "Request format: #{request.format}"
    Rails.logger.info "Request headers: #{request.headers['Accept']}"

    unless ServiceConfiguration.active?("company_linkedin_discovery")
      render json: { success: false, message: "LinkedIn discovery service is disabled" }
      return
    end

    # Get postal code from params
    postal_code = params[:postal_code]&.strip
    batch_size = params[:batch_size]&.to_i || 100

    # Validate postal code is provided and is 4 digits
    if postal_code.blank?
      render json: { success: false, message: "Postal code is required" }
      return
    end
    
    unless postal_code.match?(/\A\d{4}\z/)
      render json: { success: false, message: "Postal code must be exactly 4 digits" }
      return
    end

    # Validate batch size is positive and reasonable
    if batch_size <= 0
      render json: { success: false, message: "Batch size must be greater than 0" }
      return
    end

    if batch_size > 1000
      render json: { success: false, message: "Cannot queue more than 1000 companies at once" }
      return
    end

    # Get available companies by postal code that need LinkedIn discovery
    available_companies = Company.where(postal_code: postal_code)
                                .where.not(operating_revenue: nil)
                                .needing_service("company_linkedin_discovery")
                                .order(operating_revenue: :desc)
    
    available_count = available_companies.count

    # Debug logging
    File.open(Rails.root.join('tmp', 'postal_code_debug.log'), 'a') do |f|
      f.puts "Available companies count: #{available_count}"
    end
    
    # Check if we have companies for this postal code
    if available_count == 0
      File.open(Rails.root.join('tmp', 'postal_code_debug.log'), 'a') do |f|
        f.puts "No companies found - returning warning"
      end
      
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("body", 
            partial: "shared/toast_notification", 
            locals: { 
              message: "No companies found in postal code #{postal_code} with operating revenue data", 
              type: "warning",
              duration: 5000
            }
          )
        end
        format.json do
          render json: {
            success: false,
            message: "No companies found in postal code #{postal_code} with operating revenue data",
            available_count: 0,
            postal_code: postal_code
          }
        end
      end
      return
    end

    # Check Google API quota before queuing jobs
    quota_check = perform_google_api_quota_check(batch_size)
    unless quota_check[:available]
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("body", 
            partial: "shared/toast_notification", 
            locals: { 
              message: quota_check[:message], 
              type: "warning",
              duration: 8000
            }
          )
        end
        format.json do
          render json: {
            success: false,
            message: quota_check[:message],
            quota_used: quota_check[:used],
            quota_limit: quota_check[:limit],
            quota_remaining: quota_check[:remaining]
          }
        end
      end
      return
    end

    if batch_size > available_count
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("body", 
            partial: "shared/toast_notification", 
            locals: { 
              message: "Only #{available_count} companies available in postal code #{postal_code}, but #{batch_size} were requested", 
              type: "warning",
              duration: 5000
            }
          )
        end
        format.json do
          render json: {
            success: false,
            message: "Only #{available_count} companies available in postal code #{postal_code}, but #{batch_size} were requested",
            available_count: available_count,
            postal_code: postal_code
          }
        end
      end
      return
    end

    companies = available_companies.limit(batch_size)

    queued = 0
    
    # Debug logging
    File.open(Rails.root.join('tmp', 'postal_code_debug.log'), 'a') do |f|
      f.puts "About to queue #{companies.count} companies"
    end
    
    companies.each do |company|
      CompanyLinkedinDiscoveryWorker.perform_async(company.id)
      queued += 1
    end
    
    # Debug logging
    File.open(Rails.root.join('tmp', 'postal_code_debug.log'), 'a') do |f|
      f.puts "Successfully queued #{queued} companies"
    end

    # Invalidate cache immediately when queue changes
    Rails.cache.delete("service_stats_data")

    respond_to do |format|
      format.turbo_stream do
        # Debug logging
        File.open(Rails.root.join('tmp', 'postal_code_debug.log'), 'a') do |f|
          f.puts "Rendering turbo stream response"
        end
        
        # Get fresh stats data for immediate update
        stats_data = calculate_service_stats
        queue_stats = get_queue_stats
        
        render turbo_stream: [
          turbo_stream.replace(
            "company_queue_statistics", 
            partial: "companies/queue_statistics", 
            locals: { queue_stats: queue_stats }
          ),
          turbo_stream.replace(
            "company_linkedin_discovery_stats",
            partial: "companies/service_stats",
            locals: {
              service_name: "company_linkedin_discovery",
              companies_needing: stats_data[:linkedin_needing],
              companies_potential: stats_data[:linkedin_potential],
              queue_depth: queue_stats["company_linkedin_discovery"] || 0
            }
          ),
          turbo_stream.append(
            "toast-container",
            partial: "shared/toast_notification",
            locals: { 
              message: "Queued #{queued} companies from postal code #{postal_code} for LinkedIn discovery",
              type: "success"
            }
          )
        ]
      end
      format.json do
        render json: {
          success: true,
          message: "Queued #{queued} companies from postal code #{postal_code} for LinkedIn discovery",
          queued_count: queued,
          available_count: available_count,
          postal_code: postal_code,
          batch_size: batch_size,
          queue_stats: get_queue_stats
        }
      end
      format.html do
        flash[:notice] = "Queued #{queued} companies from postal code #{postal_code} for LinkedIn discovery"
        redirect_to companies_path
      end
    end
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
    available_companies = Company.by_country(@selected_country).needing_service("company_employee_discovery")
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
  def set_country
    if params[:country].present? && Company.exists?(source_country: params[:country])
      session[:selected_country] = params[:country]
    end
    redirect_to companies_path
  end

  # GET /companies/search_suggestions
  def search_suggestions
    query = params[:q]&.strip
    limit = [params[:limit]&.to_i || 10, 50].min # Max 50 suggestions

    if query.blank? || query.length < 2
      render json: { suggestions: [] }
      return
    end

    # Search companies by name and registration number
    companies = Company.by_country(@selected_country)
                      .where(
                        "company_name ILIKE :query OR registration_number ILIKE :query",
                        query: "%#{query}%"
                      )
                      .select(:id, :company_name, :registration_number)
                      .limit(limit)
                      .order(:company_name)

    suggestions = companies.map do |company|
      {
        id: company.id,
        company_name: company.company_name,
        registration_number: company.registration_number
      }
    end

    render json: { suggestions: suggestions }
  end

  # GET /companies/postal_code_preview
  def postal_code_preview
    postal_code = params[:postal_code]&.strip
    batch_size = params[:batch_size]&.to_i || 100

    if postal_code.blank?
      render json: { 
        count: 0, 
        postal_code: postal_code,
        batch_size: batch_size,
        revenue_range: nil 
      }
      return
    end

    # Get companies by postal code that need LinkedIn discovery (same logic as queue method)
    companies = Company.where(postal_code: postal_code)
                      .where.not(operating_revenue: nil)
                      .needing_service("company_linkedin_discovery")
                      .order(operating_revenue: :desc)
    
    count = companies.count
    
    revenue_range = if count > 0
      limited_companies = companies.limit(batch_size)
      {
        highest: format_revenue(companies.first.operating_revenue),
        lowest: format_revenue(limited_companies.last&.operating_revenue || companies.first.operating_revenue)
      }
    else
      nil
    end

    # Calculate batch size options based on available count
    batch_size_options = calculate_batch_size_options(count)
    
    render json: {
      count: count,
      postal_code: postal_code,
      batch_size: batch_size,
      batch_size_options: batch_size_options,
      revenue_range: revenue_range
    }
  end

  def service_stats
    respond_to do |format|
      format.turbo_stream do
        # Cache the stats for 1 second to ensure real-time updates
        stats_data = Rails.cache.fetch("service_stats_data", expires_in: 1.second) do
          calculate_service_stats
        end

        queue_stats = get_queue_stats

        render turbo_stream: [
          turbo_stream.replace("company_financials_stats",
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
              companies_potential: stats_data[:linkedin_potential],
              queue_depth: queue_stats["company_linkedin_discovery"] || 0
            }
          ),
          turbo_stream.replace("company_queue_statistics",
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

  def queue_linkedin_discovery_internal
    @company = Company.find(params[:id])
    
    unless ServiceConfiguration.active?("linkedin_discovery_internal")
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "LinkedIn Discovery Internal service is disabled"
          render turbo_stream: turbo_stream.replace(
            "linkedin-discovery-internal",
            LinkedinDiscoveryInternalComponent.new(company: @company)
          )
        end
        format.json { render json: { success: false, message: "Service is disabled" } }
      end
      return
    end

    sales_navigator_url = params[:sales_navigator_url]
    
    if sales_navigator_url.blank?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Sales Navigator URL is required"
          render turbo_stream: turbo_stream.replace(
            "linkedin-discovery-internal",
            LinkedinDiscoveryInternalComponent.new(company: @company)
          )
        end
        format.json { render json: { success: false, message: "Sales Navigator URL required" } }
      end
      return
    end

    begin
      # Create service audit log
      audit_log = ServiceAuditLog.create!(
        auditable: @company,
        service_name: "linkedin_discovery_internal",
        operation_type: "queue_individual",
        status: "pending",
        table_name: @company.class.table_name,
        record_id: @company.id.to_s,
        columns_affected: ["linkedin_internal_sales_navigator_url"],
        metadata: {
          action: "manual_queue",
          user_id: current_user.id,
          sales_navigator_url: sales_navigator_url,
          timestamp: Time.current
        }
      )

      # Queue the job
      LinkedinDiscoveryInternalWorker.perform_async(@company.id, sales_navigator_url)
      
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Company queued for LinkedIn Discovery Internal processing"
          render turbo_stream: turbo_stream.replace(
            "linkedin-discovery-internal",
            LinkedinDiscoveryInternalComponent.new(company: @company.reload)
          )
        end
        format.json { render json: { success: true, message: "Company queued successfully" } }
      end
    rescue StandardError => e
      Rails.logger.error "Failed to queue LinkedIn Discovery Internal: #{e.message}"
      
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Failed to queue company: #{e.message}"
          render turbo_stream: turbo_stream.replace(
            "linkedin-discovery-internal",
            LinkedinDiscoveryInternalComponent.new(company: @company)
          )
        end
        format.json { render json: { success: false, message: e.message } }
      end
    end
  end

  def check_google_api_quota
    batch_size = params[:batch_size].to_i
    quota_check = perform_google_api_quota_check(batch_size)
    
    render json: quota_check
  end

  private
  
  def calculate_batch_size_options(available_count)
    base_options = [10, 25, 50, 100, 200, 500, 1000]
    
    if available_count > 0
      # Only show options that don't exceed available company count
      valid_options = base_options.select { |option| option <= available_count }
      
      # Always include the exact available count if it's not already in the list
      # and it's greater than the largest valid option
      if valid_options.empty? || available_count < base_options.first
        # If available count is less than 10, just show that number
        valid_options = [available_count]
      elsif available_count > valid_options.last
        valid_options << available_count
      end
      
      valid_options.sort
    else
      # If no companies available, return empty array
      []
    end
  end

  def perform_google_api_quota_check(requested_jobs)
    # Calculate estimated API calls for the requested jobs
    # With optimized queries: each job makes ~3 API calls on average
    estimated_calls = requested_jobs * 3

    # Count API calls made today (successful + rate limited)
    # This tracks actual Google API usage regardless of our job status
    today_jobs = ServiceAuditLog
      .where(service_name: "company_linkedin_discovery")
      .where("created_at > ?", 24.hours.ago)
      .where(status: [ServiceAuditLog::STATUS_SUCCESS, ServiceAuditLog::STATUS_RATE_LIMITED])
      .count

    # Estimate API calls made today
    api_calls_today = today_jobs * 3

    # Check for recent rate limiting (indicates quota exhaustion)
    recent_rate_limited = ServiceAuditLog
      .where(service_name: "company_linkedin_discovery", status: ServiceAuditLog::STATUS_RATE_LIMITED)
      .where("created_at > ?", 2.hours.ago)
      .exists?

    # Get quota limits from configuration or use defaults
    daily_quota_limit = Rails.application.credentials.dig(:google, :daily_quota_limit) || 10000
    safety_buffer = (daily_quota_limit * 0.1).to_i # 10% safety buffer

    # Calculate remaining quota
    remaining_quota = daily_quota_limit - api_calls_today - safety_buffer

    # Check if we have quota for the requested jobs
    if recent_rate_limited
      {
        available: false,
        message: "Google API recently hit rate limits. Processing temporarily paused to prevent quota exhaustion.",
        used: api_calls_today,
        limit: daily_quota_limit,
        remaining: remaining_quota,
        reason: "recent_rate_limited"
      }
    elsif estimated_calls > remaining_quota
      {
        available: false,
        message: "Insufficient Google API quota. Need #{estimated_calls} calls but only #{remaining_quota} remaining today.",
        used: api_calls_today,
        limit: daily_quota_limit,
        remaining: remaining_quota,
        reason: "quota_insufficient"
      }
    else
      {
        available: true,
        message: "Quota available",
        used: api_calls_today,
        limit: daily_quota_limit,
        remaining: remaining_quota,
        estimated_usage: estimated_calls
      }
    end
  end

  def set_selected_country
    # Get available countries
    available_countries = Company.distinct.pluck(:source_country).compact.sort

    # Set selected country from session, params, or default to first available
    @selected_country = session[:selected_country] || params[:country]

    # Validate and set default if needed
    if @selected_country.blank? || !available_countries.include?(@selected_country)
      @selected_country = available_countries.first
      session[:selected_country] = @selected_country
    end
  end

  def set_company
    @company = Company.find(params[:id])
  end

  def format_revenue(amount)
    return 'N/A' unless amount

    if amount >= 1_000_000_000
      "#{(amount / 1_000_000_000.0).round(1)}B NOK"
    elsif amount >= 1_000_000
      "#{(amount / 1_000_000.0).round(1)}M NOK" 
    elsif amount >= 1_000
      "#{(amount / 1_000.0).round(0)}K NOK"
    else
      "#{amount} NOK"
    end
  end

  def calculate_service_stats
    {
      financial_needing: Company.by_country(@selected_country).needing_service("company_financial_data").count,
      web_discovery_needing: Company.by_country(@selected_country).needing_service("company_web_discovery").count,
      web_discovery_potential: Company.by_country(@selected_country).where("operating_revenue > ?", 10_000_000).count,
      linkedin_needing: Company.by_country(@selected_country).needing_service("company_linkedin_discovery").count,
      linkedin_potential: Company.by_country(@selected_country).linkedin_discovery_potential.count
    }
  end

  def company_params
    params.require(:company).permit(
      :registration_number, :company_name, :organization_form_code,
      :organization_form_description, :source_country, :source_registry,
      :website, :email, :phone, :mobile, :linkedin_url, :linkedin_ai_url,
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
      # Count total services processed from ServiceAuditLog for company services
      company_services = [ "company_financials", "company_web_discovery", "company_linkedin_discovery", "company_employee_discovery" ]

      # Use JOIN instead of plucking all IDs to avoid massive IN clause
      stats[:total_processed] = ServiceAuditLog
        .joins("INNER JOIN companies ON companies.id = service_audit_logs.auditable_id")
        .where(
          service_audit_logs: {
            auditable_type: "Company",
            service_name: company_services,
            status: ServiceAuditLog::STATUS_SUCCESS
          },
          companies: { source_country: @selected_country }
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
