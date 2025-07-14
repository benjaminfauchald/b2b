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
      
      Rails.logger.info "🚀 [QUEUE] Enqueuing PhantomBuster job: company_id=#{company_id}, service=#{service_type}, job_id=#{job_data[:job_id]}"
      
      # Add to Redis queue
      redis.rpush(REDIS_KEY, job_data.to_json)
      queue_length = redis.llen(REDIS_KEY)
      Rails.logger.info "📝 [QUEUE] Job added to queue. New queue length: #{queue_length}"
      
      # Check lock status
      lock_exists = redis.exists?(LOCK_KEY)
      current_job = redis.get(CURRENT_JOB_KEY)
      
      Rails.logger.info "🔍 [QUEUE] Lock status: exists=#{lock_exists}, current_job=#{current_job.present? ? 'yes' : 'none'}"
      
      # Only process if no job is currently running
      # This prevents concurrent launches when multiple jobs are queued rapidly
      unless lock_exists
        Rails.logger.info "▶️  [QUEUE] No job currently processing, starting queue processing"
        process_next_job
      else
        Rails.logger.info "⏸️  [QUEUE] Job already processing, added to queue for later processing"
      end
      
      job_data[:job_id]
    end
    
    # Process the next job in the queue (if no job is currently running)
    def process_next_job
      Rails.logger.info "🔄 [QUEUE] Attempting to process next job..."
      
      # Try to acquire lock for processing
      lock_acquired = redis.set(LOCK_KEY, Time.current.to_i, nx: true, ex: LOCK_TIMEOUT)
      
      Rails.logger.info "🔒 [QUEUE] Lock acquisition attempt: #{lock_acquired ? 'SUCCESS' : 'FAILED'}"
      
      unless lock_acquired
        # Check if lock is stale
        lock_timestamp = redis.get(LOCK_KEY).to_i
        Rails.logger.info "🕐 [QUEUE] Checking stale lock: timestamp=#{lock_timestamp}, cutoff=#{LOCK_TIMEOUT.seconds.ago.to_i}"
        
        if lock_timestamp < LOCK_TIMEOUT.seconds.ago.to_i
          Rails.logger.warn "⚠️  [QUEUE] Detected stale PhantomBuster processing lock, clearing..."
          redis.del(LOCK_KEY, CURRENT_JOB_KEY)
          # Try again
          lock_acquired = redis.set(LOCK_KEY, Time.current.to_i, nx: true, ex: LOCK_TIMEOUT)
          Rails.logger.info "🔒 [QUEUE] Retry lock acquisition: #{lock_acquired ? 'SUCCESS' : 'FAILED'}"
        else
          Rails.logger.info "⏸️  [QUEUE] Lock is fresh, another job is actively processing"
        end
      end
      
      unless lock_acquired
        Rails.logger.info "❌ [QUEUE] Could not acquire lock, aborting"
        return false
      end
      
      begin
        # Get next job from queue
        queue_length_before = redis.llen(REDIS_KEY)
        Rails.logger.info "📊 [QUEUE] Queue length before pop: #{queue_length_before}"
        
        job_json = redis.lpop(REDIS_KEY)
        
        unless job_json
          Rails.logger.info "📭 [QUEUE] No jobs in queue, releasing lock"
          redis.del(LOCK_KEY, CURRENT_JOB_KEY)
          return false
        end
        
        queue_length_after = redis.llen(REDIS_KEY)
        Rails.logger.info "📊 [QUEUE] Queue length after pop: #{queue_length_after}"
        
        job_data = JSON.parse(job_json)
        company_id = job_data['company_id']
        job_id = job_data['job_id']
        
        Rails.logger.info "▶️  [QUEUE] Processing PhantomBuster job: company_id=#{company_id}, job_id=#{job_id}"
        
        # Store current job info
        redis.set(CURRENT_JOB_KEY, job_json, ex: LOCK_TIMEOUT)
        Rails.logger.info "💾 [QUEUE] Stored current job in Redis"
        
        # Launch the actual PhantomBuster job
        Rails.logger.info "🚀 [QUEUE] Launching PhantomBuster job..."
        launch_phantom_job(job_data)
        
        Rails.logger.info "✅ [QUEUE] Job processing initiated successfully"
        true
      rescue StandardError => e
        Rails.logger.error "❌ [QUEUE] Failed to process next PhantomBuster job: #{e.class} - #{e.message}"
        Rails.logger.error "📍 [QUEUE] Backtrace: #{e.backtrace.first(3).join(' | ')}"
        # Release lock on error
        redis.del(LOCK_KEY, CURRENT_JOB_KEY)
        Rails.logger.info "🔓 [QUEUE] Released lock due to error"
        false
      end
    end
    
    # Called when a PhantomBuster job completes (success or failure)
    def job_completed(container_id, status)
      Rails.logger.info "🏁 [COMPLETION] PhantomBuster job completed: container_id=#{container_id}, status=#{status}"
      
      # Check current state before clearing
      current_job = redis.get(CURRENT_JOB_KEY)
      lock_exists = redis.exists?(LOCK_KEY)
      queue_length = redis.llen(REDIS_KEY)
      
      Rails.logger.info "📊 [COMPLETION] Pre-cleanup state: lock=#{lock_exists}, current_job=#{current_job.present? ? 'yes' : 'none'}, queue_length=#{queue_length}"
      
      # Clear current job and release lock
      redis.del(LOCK_KEY, CURRENT_JOB_KEY)
      Rails.logger.info "🔓 [COMPLETION] Cleared lock and current job"
      
      # Check queue after cleanup
      queue_length_after = redis.llen(REDIS_KEY)
      Rails.logger.info "📊 [COMPLETION] Queue length after cleanup: #{queue_length_after}"
      
      if queue_length_after > 0
        Rails.logger.info "🔄 [COMPLETION] Queue has #{queue_length_after} jobs waiting, attempting to process next..."
        # Process next job in queue
        next_job_started = process_next_job
        
        Rails.logger.info "🎯 [COMPLETION] Next job #{next_job_started ? 'STARTED successfully' : 'NOT STARTED (failed or queue empty)'}"
      else
        Rails.logger.info "📭 [COMPLETION] Queue is empty, no next job to process"
        next_job_started = false
      end
      
      next_job_started
    end
    
    # Get current queue status
    def queue_status
      {
        queue_length: redis.llen(REDIS_KEY),
        is_processing: redis.exists?(LOCK_KEY),
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
      
      Rails.logger.info "🎬 [LAUNCH] Launching phantom job: company_id=#{company_id}, service=#{service_type}, job_id=#{job_id}"
      
      company = Company.find(company_id)
      Rails.logger.info "🏢 [LAUNCH] Company: #{company.company_name}"
      
      case service_type
      when 'profile_extraction'
        webhook_url = webhook_url_for_service(service_type)
        Rails.logger.info "🔗 [LAUNCH] Webhook URL: #{webhook_url}"
        
        # Launch PersonProfileExtractionWorker with webhook mode
        # Note: Sidekiq requires all arguments to be JSON-serializable
        worker_args = options.merge(
          'webhook_mode' => true,
          'queue_job_id' => job_id,
          'webhook_url' => webhook_url
        )
        
        Rails.logger.info "🚀 [LAUNCH] Enqueuing PersonProfileExtractionWorker with args: #{worker_args.keys.join(', ')}"
        
        PersonProfileExtractionWorker.perform_async(
          company_id,
          worker_args
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