# frozen_string_literal: true

class PhantomBusterSequentialQueue
  REDIS_KEY = 'phantom_buster:sequential_queue'
  LOCK_KEY = 'phantom_buster:processing_lock'
  CURRENT_JOB_KEY = 'phantom_buster:current_job'
  LOCK_TIMEOUT = 30.minutes.to_i # Safety timeout for stuck jobs
  
  class << self
    # Queue a new PhantomBuster job for sequential processing
    def enqueue_job(company_id, service_type = 'profile_extraction', options = {})
      job_data = {
        company_id: company_id,
        service_type: service_type,
        queued_at: Time.current.to_f,
        options: options.to_h,
        job_id: SecureRandom.uuid
      }
      
      Rails.logger.info "Enqueuing PhantomBuster job: company_id=#{company_id}, service=#{service_type}"
      
      # Add to Redis queue
      redis.rpush(REDIS_KEY, job_data.to_json)
      
      # Only process if no job is currently running
      # This prevents concurrent launches when multiple jobs are queued rapidly
      unless redis.exists?(LOCK_KEY) == 1
        Rails.logger.info "No job currently processing, starting queue processing"
        process_next_job
      else
        Rails.logger.info "Job already processing, added to queue for later"
      end
      
      job_data[:job_id]
    end
    
    # Process the next job in the queue (if no job is currently running)
    def process_next_job
      # Try to acquire lock for processing
      lock_acquired = redis.set(LOCK_KEY, Time.current.to_i, nx: true, ex: LOCK_TIMEOUT)
      
      unless lock_acquired
        # Check if lock is stale
        lock_timestamp = redis.get(LOCK_KEY).to_i
        if lock_timestamp < LOCK_TIMEOUT.seconds.ago.to_i
          Rails.logger.warn "Detected stale PhantomBuster processing lock, clearing..."
          redis.del(LOCK_KEY, CURRENT_JOB_KEY)
          # Try again
          lock_acquired = redis.set(LOCK_KEY, Time.current.to_i, nx: true, ex: LOCK_TIMEOUT)
        end
      end
      
      return false unless lock_acquired
      
      begin
        # Get next job from queue
        job_json = redis.lpop(REDIS_KEY)
        return false unless job_json
        
        job_data = JSON.parse(job_json)
        Rails.logger.info "Processing next PhantomBuster job: #{job_data['job_id']}"
        
        # Store current job info
        redis.set(CURRENT_JOB_KEY, job_json, ex: LOCK_TIMEOUT)
        
        # Launch the actual PhantomBuster job
        launch_phantom_job(job_data)
        
        true
      rescue StandardError => e
        Rails.logger.error "Failed to process next PhantomBuster job: #{e.message}"
        # Release lock on error
        redis.del(LOCK_KEY, CURRENT_JOB_KEY)
        false
      end
    end
    
    # Called when a PhantomBuster job completes (success or failure)
    def job_completed(container_id, status)
      Rails.logger.info "PhantomBuster job completed: container_id=#{container_id}, status=#{status}"
      
      # Clear current job and release lock
      redis.del(LOCK_KEY, CURRENT_JOB_KEY)
      
      # Process next job in queue
      next_job_started = process_next_job
      
      Rails.logger.info "Next job #{next_job_started ? 'started' : 'not started (queue empty)'}"
      
      next_job_started
    end
    
    # Get current queue status
    def queue_status
      {
        queue_length: redis.llen(REDIS_KEY),
        is_processing: redis.exists?(LOCK_KEY) == 1,
        current_job: current_job_info,
        lock_timestamp: redis.get(LOCK_KEY)&.to_i
      }
    end
    
    # Get queue contents (for admin/debugging)
    def queue_contents
      redis.lrange(REDIS_KEY, 0, -1).map do |job_json|
        JSON.parse(job_json)
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse queue contents: #{e.message}"
      []
    end
    
    # Clear the entire queue (emergency use)
    def clear_queue!
      cleared_jobs = redis.del(REDIS_KEY, LOCK_KEY, CURRENT_JOB_KEY)
      Rails.logger.warn "Cleared PhantomBuster queue and locks, removed #{cleared_jobs} keys"
      cleared_jobs
    end
    
    # Remove a specific job from queue by job_id
    def remove_job(job_id)
      queue_contents.each_with_index do |job_data, index|
        if job_data['job_id'] == job_id
          # Remove from specific position
          redis.lrem(REDIS_KEY, 1, job_data.to_json)
          Rails.logger.info "Removed job #{job_id} from queue"
          return true
        end
      end
      false
    end
    
    # Force release lock (emergency use)
    def force_release_lock!
      redis.del(LOCK_KEY, CURRENT_JOB_KEY)
      Rails.logger.warn "Forcefully released PhantomBuster processing lock"
      true
    end
    
    # Check if queue has jobs for a specific company
    def has_jobs_for_company?(company_id)
      queue_contents.any? { |job| job['company_id'] == company_id }
    end
    
    # Get position of next job for a company
    def company_queue_position(company_id)
      queue_contents.each_with_index do |job, index|
        return index + 1 if job['company_id'] == company_id
      end
      nil
    end
    
    private
    
    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    end
    
    def current_job_info
      current_job_json = redis.get(CURRENT_JOB_KEY)
      return nil unless current_job_json
      
      JSON.parse(current_job_json)
    rescue JSON::ParserError
      nil
    end
    
    def launch_phantom_job(job_data)
      company_id = job_data['company_id']
      service_type = job_data['service_type']
      options = job_data['options'] || {}
      job_id = job_data['job_id']
      
      company = Company.find(company_id)
      
      case service_type
      when 'profile_extraction'
        # Launch PersonProfileExtractionWorker with webhook mode
        # Note: Sidekiq requires all arguments to be JSON-serializable
        PersonProfileExtractionWorker.perform_async(
          company_id,
          options.merge(
            'webhook_mode' => true,
            'queue_job_id' => job_id,
            'webhook_url' => webhook_url_for_service(service_type)
          )
        )
      else
        raise "Unknown service type: #{service_type}"
      end
      
      Rails.logger.info "Launched PhantomBuster job: company_id=#{company_id}, service=#{service_type}, job_id=#{job_id}"
    end
    
    def webhook_url_for_service(service_type)
      case service_type
      when 'profile_extraction'
        # Build the webhook URL for profile extraction
        # Using plain URL without query params as it worked when configured in PhantomBuster UI
        base_url = ENV.fetch('APP_BASE_URL', 'https://app.connectica.no')
        "#{base_url}/webhooks/phantombuster/profile_extraction"
      else
        raise "No webhook URL configured for service: #{service_type}"
      end
    end
  end
end