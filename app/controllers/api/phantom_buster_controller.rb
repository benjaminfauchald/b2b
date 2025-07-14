# frozen_string_literal: true

module Api
  class PhantomBusterController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!, only: [:restart_queue]

    def status
      # Get current queue status from PhantomBusterSequentialQueue
      queue_status = PhantomBusterSequentialQueue.queue_status
      
      response_data = {
        is_processing: queue_status[:is_processing],
        queue_length: queue_status[:queue_length]
      }
      
      # If processing, get the current company details
      if queue_status[:is_processing] && queue_status[:current_job].present?
        current_job = queue_status[:current_job]
        company_id = current_job['company_id']
        
        if company_id
          company = Company.find_by(id: company_id)
          if company
            response_data[:current_company] = company.company_name
            response_data[:current_company_id] = company.id
            
            # Calculate duration if we have a queued_at timestamp
            if current_job['queued_at']
              started_at = Time.at(current_job['queued_at'])
              response_data[:current_job_duration] = (Time.current - started_at).to_i
              
              # Estimate completion (PhantomBuster typically takes 5 minutes)
              estimated_completion = started_at + 5.minutes
              response_data[:estimated_completion] = estimated_completion.iso8601
            end
          end
        end
      end
      
      render json: response_data
    rescue StandardError => e
      Rails.logger.error "Error fetching PhantomBuster status: #{e.message}"
      render json: { 
        is_processing: false, 
        queue_length: 0,
        error: 'Unable to fetch status'
      }, status: :internal_server_error
    end

    def restart_queue
      Rails.logger.info "Admin restart queue requested by user #{current_user.email}"
      
      # Get current queue status first for logging
      queue_status = PhantomBusterSequentialQueue.queue_status
      
      begin
        # Force release any stuck locks
        PhantomBusterSequentialQueue.force_release_lock!
        
        # Log the restart action
        ServiceAuditLog.create!(
          service_name: 'phantom_buster_admin',
          action: 'restart_queue',
          status: 'success',
          auditable_type: 'System',
          auditable_id: nil,
          metadata: {
            admin_user: current_user.email,
            previous_queue_status: queue_status,
            timestamp: Time.current
          }
        )
        
        # Start processing the next job if queue has items
        PhantomBusterSequentialQueue.process_next_job
        
        Rails.logger.info "Queue restart completed successfully"
        
        render json: { 
          success: true, 
          message: 'Queue restarted successfully',
          action_taken: 'force_release_lock_and_process_next'
        }
        
      rescue StandardError => e
        Rails.logger.error "Error restarting queue: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Log the failed restart
        ServiceAuditLog.create!(
          service_name: 'phantom_buster_admin',
          action: 'restart_queue',
          status: 'error',
          auditable_type: 'System',
          auditable_id: nil,
          metadata: {
            admin_user: current_user.email,
            error_message: e.message,
            timestamp: Time.current
          }
        )
        
        render json: { 
          success: false, 
          error: 'Failed to restart queue',
          details: e.message
        }, status: :internal_server_error
      end
    end

    private

    def require_admin!
      unless current_user&.admin?
        render json: { error: 'Admin access required' }, status: :forbidden
      end
    end
  end
end