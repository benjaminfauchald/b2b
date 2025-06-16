class ServicePerformanceStat < ApplicationRecord
  # This is a read-only view model
  self.table_name = 'service_performance_stats'
  self.primary_key = 'service_name'

  # Make it read-only
  def readonly?
    true
  end

  # Scopes
  scope :high_success_rate, ->(threshold = 95) { where('success_rate_percent >= ?', threshold) }
  scope :low_success_rate, ->(threshold = 80) { where('success_rate_percent < ?', threshold) }
  scope :slow_services, ->(threshold_ms = 5000) { where('avg_duration_ms > ?', threshold_ms) }
  scope :fast_services, ->(threshold_ms = 1000) { where('avg_duration_ms <= ?', threshold_ms) }
  scope :recent_activity, -> { where('last_run_at > ?', 24.hours.ago) }
  scope :recent, -> { order(last_run_at: :desc) }
  scope :by_success_rate, -> { order(success_rate_percent: :desc) }
  scope :by_duration, -> { order(avg_duration_ms: :desc) }

  # Class methods
  def self.for_service(service_name)
    find_by(service_name: service_name)
  end

  def self.top_performers(limit = 10)
    order(success_rate_percent: :desc, avg_duration_ms: :asc).limit(limit)
  end

  def self.problem_services(success_threshold = 80, duration_threshold = 10000)
    where('success_rate_percent < ? OR avg_duration_ms > ?', success_threshold, duration_threshold)
  end

  def self.refresh
    connection.execute('REFRESH MATERIALIZED VIEW service_performance_stats')
  end

  def self.find_by_service_name(service_name)
    find_by(service_name: service_name)
  end

  # Instance methods
  def success_rate
    success_rate_percent / 100.0
  end

  def failure_rate
    1 - success_rate
  end

  def failure_rate_last_hour
    failure_rate_last_hour_percent / 100.0
  end

  def healthy?
    failure_rate_last_hour < 0.1 # Less than 10% failure rate in last hour
  end

  def needs_attention?
    failure_rate_last_hour > 0.2 # More than 20% failure rate in last hour
  end

  def critical?
    failure_rate_last_hour > 0.5 # More than 50% failure rate in last hour
  end

  def avg_duration_seconds
    return nil unless avg_duration_ms
    
    (avg_duration_ms / 1000.0).round(2)
  end

  def min_duration_seconds
    return nil unless min_duration_ms
    
    (min_duration_ms / 1000.0).round(2)
  end

  def max_duration_seconds
    return nil unless max_duration_ms
    
    (max_duration_ms / 1000.0).round(2)
  end

  def failure_rate_percent
    return 0 if total_runs.zero?
    
    100.0 - success_rate_percent
  end

  def runs_per_day
    return 0 unless first_run_at && last_run_at
    
    days = ((last_run_at - first_run_at) / 1.day).round(1)
    return total_runs if days < 1
    
    (total_runs / days).round(1)
  end

  def status_summary
    {
      healthy: healthy?,
      needs_attention: needs_attention?,
      success_rate: success_rate_percent,
      avg_duration_seconds: avg_duration_seconds,
      total_runs: total_runs,
      last_run: last_run_at
    }
  end
end 