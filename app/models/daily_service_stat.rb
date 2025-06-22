class DailyServiceStat < ApplicationRecord
  # Set table name to match the materialized view
  self.table_name = 'daily_service_stats'
  
  # Make the model read-only since it's a materialized view
  def readonly?
    true
  end

  # Relationships
  belongs_to :service_configuration, foreign_key: 'service_name', primary_key: 'service_name', optional: true

  # Validations
  validates :service_name, presence: true
  validates :date, presence: true
  validates :total_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :successful_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :failed_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :avg_execution_time_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :p95_execution_time_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :p99_execution_time_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :error_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  # Scopes
  scope :recent, -> { order(date: :desc) }
  scope :for_service, ->(service_name) { where(service_name: service_name) }
  scope :with_errors, -> { where('error_rate > 0') }
  scope :high_error_rate, -> { where('error_rate > 5') }
  scope :critical_error_rate, -> { where('error_rate > 20') }
  scope :slow_services, -> { where('p95_execution_time_ms > 1000') }
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :last_n_days, ->(days = 7) { where('date >= ?', days.days.ago.to_date) }
  scope :today, -> { where(date: Date.current) }
  scope :yesterday, -> { where(date: Date.current - 1.day) }
  scope :this_week, -> { where('date >= ?', Date.current.beginning_of_week) }
  scope :last_week, -> { where(date: (Date.current.beginning_of_week - 7.days)..(Date.current.beginning_of_week - 1.day)) }

  # Class methods
  def self.refresh_materialized_view
    ActiveRecord::Base.connection.execute('REFRESH MATERIALIZED VIEW daily_service_stats')
  end

  def self.top_error_services(limit = 5)
    where('total_runs > 10')
      .order(error_rate: :desc)
      .limit(limit)
  end

  def self.top_slowest_services(limit = 5)
    where('total_runs > 10')
      .order(p95_execution_time_ms: :desc)
      .limit(limit)
  end

  # Helper methods for dashboard display
  def success_rate
    100 - error_rate
  end

  def success_rate_formatted
    "#{success_rate.round(2)}%"
  end

  def error_rate_formatted
    "#{error_rate.round(2)}%"
  end

  def avg_execution_time_formatted
    format_duration(avg_execution_time_ms)
  end

  def p95_execution_time_formatted
    format_duration(p95_execution_time_ms)
  end

  def p99_execution_time_formatted
    format_duration(p99_execution_time_ms)
  end

  def status_class
    if error_rate > 20
      'critical'
    elsif error_rate > 5
      'warning'
    else
      'success'
    end
  end

  def status_label
    if error_rate > 20
      'Critical'
    elsif error_rate > 5
      'Warning'
    else
      'Healthy'
    end
  end

  private

  def format_duration(ms)
    return '0ms' if ms.nil? || ms == 0
    
    if ms < 1000
      "#{ms.round}ms"
    else
      "#{(ms / 1000.0).round(2)}s"
    end
  end
end
