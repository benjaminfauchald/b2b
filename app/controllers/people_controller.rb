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

    @pagy, @people = pagy(people_scope)
    @queue_stats = get_queue_stats
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
              persons_needing: stats_data[:email_needing],
              queue_depth: queue_stats["person_email_extraction"] || 0
            }
          ),
          turbo_stream.replace("person_social_media_extraction_stats",
            partial: "people/service_stats",
            locals: {
              service_name: "person_social_media_extraction",
              service_title: "Social Media Extraction",
              persons_needing: stats_data[:social_media_needing],
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

  def calculate_service_stats
    {
      profile_needing: Company.needing_service("person_profile_extraction").count,
      profile_potential: Company.profile_extraction_potential.count,
      email_needing: Person.needing_service("person_email_extraction").count,
      social_media_needing: Person.needing_service("person_social_media_extraction").count
    }
  end

  def person_params
    params.require(:person).permit(
      :name, :profile_url, :title, :company_name, :location,
      :email, :phone, :connection_degree, :phantom_run_id,
      :company_id
    )
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
