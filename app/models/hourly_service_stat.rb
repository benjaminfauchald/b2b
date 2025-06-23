class HourlyServiceStat < ApplicationRecord
  # Set table name to match the materialized view
  self.table_name = "hourly_service_stats"

  # Make the model read-only since it's a materialized view
  def readonly?
    true
  end

  # Relationships
  belongs_to :service_configuration, foreign_key: "service_name", primary_key: "service_name", optional: true

  # Validations
  validates :service_name, presence: true
  validates :date, presence: true
  validates :hour, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 24 }
  validates :total_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :successful_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :failed_runs, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :avg_execution_time_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :p95_execution_time_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :p99_execution_time_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :error_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  # Scopes
  scope :recent, -> { order(date: :desc, hour: :desc) }
  scope :for_service, ->(service_name) { where(service_name: service_name) }
  scope :with_errors, -> { where("error_rate > 0") }
  scope :high_error_rate, -> { where("error_rate > 5") }
  scope :critical_error_rate, -> { where("error_rate > 20") }
  scope :slow_services, -> { where("p95_execution_time_ms > 1000") }

  # Hour-specific scopes
  scope :for_hour, ->(hour) { where(hour: hour) }
  scope :business_hours, -> { where(hour: 9..17) }
  scope :non_business_hours, -> { where.not(hour: 9..17) }
  scope :night_hours, -> { where(hour: 0..5) }

  # Date and time range scopes
  scope :for_date_and_hour_range, ->(start_datetime, end_datetime) {
    where("(date + (hour * interval '1 hour')) BETWEEN ? AND ?", start_datetime, end_datetime)
  }
  scope :last_n_hours, ->(hours = 24) {
    current_time = Time.current
    where("(date + (hour * interval '1 hour')) >= ?", current_time - hours.hours)
  }
  scope :today, -> { where(date: Date.current) }
  scope :yesterday, -> { where(date: Date.current - 1.day) }
  scope :current_hour, -> {
    now = Time.current
    where(date: now.to_date, hour: now.hour)
  }
  scope :previous_hour, -> {
    one_hour_ago = Time.current - 1.hour
    where(date: one_hour_ago.to_date, hour: one_hour_ago.hour)
  }

  # Class methods
  def self.refresh_materialized_view
    ActiveRecord::Base.connection.execute("REFRESH MATERIALIZED VIEW hourly_service_stats")
  end

  def self.top_error_services(limit = 5)
    where("total_runs > 5")
      .order(error_rate: :desc)
      .limit(limit)
  end

  def self.top_slowest_services(limit = 5)
    where("total_runs > 5")
      .order(p95_execution_time_ms: :desc)
      .limit(limit)
  end

  def self.hourly_trend(service_name, hours = 24)
    for_service(service_name)
      .last_n_hours(hours)
      .order("date ASC, hour ASC")
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
      "critical"
    elsif error_rate > 5
      "warning"
    else
      "success"
    end
  end

  def status_label
    if error_rate > 20
      "Critical"
    elsif error_rate > 5
      "Warning"
    else
      "Healthy"
    end
  end

  def hour_formatted
    "#{hour}:00"
  end

  def datetime
    DateTime.new(date.year, date.month, date.day, hour, 0, 0)
  end

  private

  def format_duration(ms)
    return "0ms" if ms.nil? || ms == 0

    if ms < 1000
      "#{ms.round}ms"
    else
      "#{(ms / 1000.0).round(2)}s"
    end
  end
end
