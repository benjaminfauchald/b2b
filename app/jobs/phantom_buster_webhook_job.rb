# frozen_string_literal: true

class PhantomBusterWebhookJob < ApplicationJob
  queue_as :phantom_webhooks
  
  # Retry with exponential backoff for webhook processing
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(webhook_payload, audit_log_id)
    audit_log = ServiceAuditLog.find(audit_log_id)
    container_id = webhook_payload['containerId']
    status = webhook_payload['status'] || webhook_payload['exitMessage']
    exit_code = webhook_payload['exitCode']
    
    Rails.logger.info "📨 [WEBHOOK] Processing PhantomBuster webhook: container_id=#{container_id}, status=#{status}, exit_code=#{exit_code}"
    Rails.logger.info "📋 [WEBHOOK] Full payload keys: #{webhook_payload.keys.join(', ')}"
    
    begin
      # Determine the actual status based on exit code and status/exitMessage
      if exit_code == 0 || status == 'finished'
        handle_job_completion(webhook_payload, audit_log)
      elsif status == 'error' || (exit_code && exit_code != 0)
        handle_job_error(webhook_payload, audit_log)
      elsif status == 'running'
        handle_job_progress(webhook_payload, audit_log)
      else
        Rails.logger.warn "Unknown PhantomBuster status: #{status}"
        # Default to completion if we have results
        if webhook_payload['resultObject'].present?
          handle_job_completion(webhook_payload, audit_log)
        end
      end

      # Update audit log with processing completion
      audit_log.update!(
        status: :success,
        completed_at: Time.current,
        metadata: audit_log.metadata.merge(
          webhook_processed_at: Time.current,
          final_status: status
        )
      )
      
    rescue StandardError => e
      Rails.logger.error "Failed to process PhantomBuster webhook: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      audit_log.update!(
        status: :failed,
        error_message: e.message,
        completed_at: Time.current
      )
      
      raise # Re-raise for Sidekiq retry
    end
  end

  private

  def handle_job_completion(webhook_payload, audit_log)
    container_id = webhook_payload['containerId']
    
    # Find the associated service audit log for the original PhantomBuster job
    phantom_audit_log = find_phantom_job_audit_log(container_id)
    
    if phantom_audit_log
      # Update the webhook audit log to have the correct auditable
      if audit_log.metadata['temp_auditable']
        audit_log.update!(
          auditable: phantom_audit_log.auditable,
          auditable_type: phantom_audit_log.auditable_type,
          auditable_id: phantom_audit_log.auditable_id
        )
      end
      # Update the original job's audit log
      phantom_audit_log.update!(
        status: :success,
        completed_at: Time.current,
        metadata: phantom_audit_log.metadata.merge(
          webhook_received_at: Time.current,
          result_url: webhook_payload['resultUrl'],
          duration: webhook_payload['duration'],
          finished_at: webhook_payload['finishedAt']
        )
      )
      
      # Process results if available
      if webhook_payload['resultUrl'].present?
        process_phantom_results(webhook_payload['resultUrl'], phantom_audit_log)
      elsif webhook_payload['resultObject'].present?
        # Results are directly in the webhook payload
        process_phantom_results_from_object(webhook_payload['resultObject'], phantom_audit_log)
      end
      
      Rails.logger.info "PhantomBuster job completed: #{container_id}"
    else
      Rails.logger.warn "Could not find audit log for container: #{container_id}"
    end
    
    # Trigger next job in queue (sequential processing)
    trigger_next_phantom_job
  end

  def handle_job_error(webhook_payload, audit_log)
    container_id = webhook_payload['containerId']
    error_message = webhook_payload['error'] || webhook_payload['message'] || 'Unknown error'
    
    # Find the associated service audit log for the original PhantomBuster job
    phantom_audit_log = find_phantom_job_audit_log(container_id)
    
    if phantom_audit_log
      phantom_audit_log.update!(
        status: :failed,
        error_message: error_message,
        completed_at: Time.current,
        metadata: phantom_audit_log.metadata.merge(
          webhook_received_at: Time.current,
          phantom_error: error_message,
          finished_at: webhook_payload['finishedAt']
        )
      )
      
      Rails.logger.error "PhantomBuster job failed: #{container_id} - #{error_message}"
    end
    
    # Still trigger next job even on failure (don't let one failure block the queue)
    trigger_next_phantom_job
  end

  def handle_job_progress(webhook_payload, audit_log)
    container_id = webhook_payload['containerId']
    progress = webhook_payload['progress']
    
    # Find and update the audit log with progress
    phantom_audit_log = find_phantom_job_audit_log(container_id)
    
    if phantom_audit_log
      phantom_audit_log.update!(
        metadata: phantom_audit_log.metadata.merge(
          progress: progress,
          last_progress_update: Time.current
        )
      )
      
      Rails.logger.info "PhantomBuster progress update: #{container_id} - #{progress}%"
    end
  end

  def find_phantom_job_audit_log(container_id)
    # Look for audit logs with this container ID in metadata
    ServiceAuditLog.where(
      service_name: 'phantom_buster_profile_extraction'
    ).where(
      "metadata->>'phantom_container_id' = ?", 
      container_id
    ).first
  end

  def process_phantom_results(result_url, audit_log)
    Rails.logger.info "Processing PhantomBuster CSV results from: #{result_url}"
    
    begin
      # Download the CSV file
      response = HTTParty.get(result_url, timeout: 30)
      raise "Failed to download results: #{response.code}" unless response.success?
      
      # Parse as JSON first (PhantomBuster typically returns JSON)
      profiles = response.parsed_response
      
      unless profiles.is_a?(Array) && profiles.any?
        Rails.logger.info "⚠️ No profiles found in results"
        audit_log.update!(
          metadata: audit_log.metadata.merge(
            profiles_processed: 0,
            result_url: result_url,
            processing_completed_at: Time.current
          )
        )
        return
      end
      
      # Get company from audit log
      company_id = audit_log.auditable_id if audit_log.auditable_type == 'Company'
      company = Company.find(company_id) if company_id
      
      if company
        # Save profiles using the existing method pattern
        profile_count = save_profiles_to_database(profiles, audit_log.metadata['phantom_container_id'], company)
        
        Rails.logger.info "✅ Processed #{profile_count} profiles from webhook results"
        
        audit_log.update!(
          metadata: audit_log.metadata.merge(
            profiles_processed: profile_count,
            result_url: result_url,
            processing_completed_at: Time.current
          )
        )
      else
        Rails.logger.error "Could not find company for audit log #{audit_log.id}"
      end
      
    rescue StandardError => e
      Rails.logger.error "Failed to process PhantomBuster results: #{e.message}"
      audit_log.update!(
        metadata: audit_log.metadata.merge(
          result_processing_error: e.message,
          result_url: result_url
        )
      )
    end
  end

  def save_profiles_to_database(profiles, phantom_run_id, company)
    inserted_count = 0
    updated_count = 0

    ActiveRecord::Base.transaction do
      profiles.each do |profile|
        begin
          # Extract the LinkedIn profile URL - prefer defaultProfileUrl which has the proper format
          profile_url = profile["defaultProfileUrl"] || profile["linkedInProfileUrl"] || profile["profileUrl"] || profile["profile_url"]
          
          # Skip if no profile URL
          if profile_url.blank?
            Rails.logger.warn "⚠️ Skipping profile without URL: #{profile.inspect}"
            next
          end
          
          # Find or initialize person by profile URL (the most unique identifier)
          person = Person.find_or_initialize_by(profile_url: profile_url)
          
          # Track if this is a new record
          is_new_record = person.new_record?
          
          # Update all attributes
          person.assign_attributes(
            company_id: company.id,
            company_name: company.company_name,
            name: profile["fullName"] || profile["name"],
            title: profile["title"] || profile["jobTitle"],
            location: profile["location"],
            email: profile["email"] || person.email, # Keep existing email if new one is blank
            phone: profile["phone"] || person.phone, # Keep existing phone if new one is blank
            connection_degree: profile["connectionDegree"] || profile["connection_degree"],
            phantom_run_id: phantom_run_id,
            profile_extracted_at: Time.current,
            profile_data: profile
          )
          
          # Save the person record
          person.save!
          
          # Update counters
          if is_new_record
            inserted_count += 1
          else
            updated_count += 1
          end

        rescue => e
          Rails.logger.warn "⚠️ Failed to save/update profile: #{e.message}"
          Rails.logger.warn "Profile data: #{profile.inspect}"
        end
      end
    end

    Rails.logger.info "✅ Processed #{profiles.length} profiles: #{inserted_count} new, #{updated_count} updated"
    inserted_count + updated_count
  end

  def process_phantom_results_from_object(result_object, audit_log)
    Rails.logger.info "Processing PhantomBuster results from webhook payload"
    
    begin
      # Parse the result object if it's a string
      profiles = if result_object.is_a?(String)
        JSON.parse(result_object)
      else
        result_object
      end
      
      unless profiles.is_a?(Array) && profiles.any?
        Rails.logger.info "⚠️ No profiles found in resultObject"
        audit_log.update!(
          metadata: audit_log.metadata.merge(
            profiles_processed: 0,
            processing_completed_at: Time.current
          )
        )
        return
      end
      
      # Get company from audit log
      company_id = audit_log.auditable_id if audit_log.auditable_type == 'Company'
      company = Company.find(company_id) if company_id
      
      if company
        # Save profiles using the existing method
        profile_count = save_profiles_to_database(profiles, audit_log.metadata['phantom_container_id'], company)
        
        Rails.logger.info "✅ Processed #{profile_count} profiles from webhook payload"
        
        audit_log.update!(
          metadata: audit_log.metadata.merge(
            profiles_processed: profile_count,
            processing_completed_at: Time.current
          )
        )
      else
        Rails.logger.error "Could not find company for audit log #{audit_log.id}"
      end
      
    rescue StandardError => e
      Rails.logger.error "Failed to process PhantomBuster results: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      audit_log.update!(
        metadata: audit_log.metadata.merge(
          result_processing_error: e.message
        )
      )
    end
  end

  def trigger_next_phantom_job
    # Signal job completion to the sequential queue
    Rails.logger.info "🔄 [WEBHOOK] Triggering next PhantomBuster job in queue"
    Rails.logger.info "📊 [WEBHOOK] About to call PhantomBusterSequentialQueue.job_completed(nil, 'completed')"
    
    # Note: We don't need the container_id here, just signal that a job completed
    # The queue manager will clear the lock and process the next job
    result = PhantomBusterSequentialQueue.job_completed(nil, 'completed')
    
    Rails.logger.info "🎯 [WEBHOOK] Queue completion result: #{result ? 'Next job started' : 'No next job started'}"
  end
end