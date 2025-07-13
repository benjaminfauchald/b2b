# frozen_string_literal: true

class PhantomBusterQueueStatusComponent < ViewComponent::Base
  def initialize(company_id: nil, show_detailed: false)
    @company_id = company_id
    @show_detailed = show_detailed
    @queue_status = PhantomBusterSequentialQueue.queue_status
    @queue_contents = @show_detailed ? PhantomBusterSequentialQueue.queue_contents : []
  end

  private

  attr_reader :company_id, :show_detailed, :queue_status, :queue_contents

  def queue_length
    queue_status[:queue_length] || 0
  end

  def is_processing?
    queue_status[:is_processing] || false
  end

  def current_job
    queue_status[:current_job]
  end

  def lock_timestamp
    queue_status[:lock_timestamp]
  end

  def current_job_company_name
    return "Unknown Company" unless current_job&.dig('company_id')
    
    company = Company.find_by(id: current_job['company_id'])
    company&.company_name || "Unknown Company"
  end

  def current_job_duration
    return nil unless current_job&.dig('queued_at')
    
    queued_at = Time.at(current_job['queued_at'])
    Time.current - queued_at
  end

  def estimated_completion_time
    return nil unless current_job_duration
    
    # Estimate based on average PhantomBuster job duration (25 minutes)
    estimated_duration = 25.minutes
    elapsed = current_job_duration
    remaining = estimated_duration - elapsed
    
    remaining > 0 ? remaining : 0
  end

  def company_queue_position
    return nil unless company_id
    
    PhantomBusterSequentialQueue.company_queue_position(company_id)
  end

  def company_has_queued_jobs?
    return false unless company_id
    
    PhantomBusterSequentialQueue.has_jobs_for_company?(company_id)
  end

  def queue_status_badge_class
    if is_processing?
      "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300"
    elsif queue_length > 0
      "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"
    else
      "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"
    end
  end

  def queue_status_text
    if is_processing?
      "Processing"
    elsif queue_length > 0
      "Queued"
    else
      "Idle"
    end
  end

  def format_duration(seconds)
    return "0s" if seconds.nil? || seconds <= 0
    
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      minutes = (seconds / 60).round
      "#{minutes}m"
    else
      hours = (seconds / 3600).round(1)
      "#{hours}h"
    end
  end

  def format_queue_time(queued_at_timestamp)
    return "Unknown" unless queued_at_timestamp
    
    queued_at = Time.at(queued_at_timestamp)
    time_ago_in_words(queued_at) + " ago"
  end

  def progress_percentage
    return 0 unless current_job_duration
    
    # Estimate progress based on typical 25-minute job duration
    estimated_duration = 25.minutes.to_f
    elapsed = current_job_duration.to_f
    
    progress = (elapsed / estimated_duration * 100).round
    [progress, 100].min # Cap at 100%
  end
end