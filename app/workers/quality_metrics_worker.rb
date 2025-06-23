class QualityMetricsWorker < ApplicationJob
  queue_as :metrics

  # Set retry options
  sidekiq_options retry: 3, backtrace: true

  # Service name for audit logging
  SERVICE_NAME = "QualityMetricsWorker".freeze

  # Redis cache keys and TTLs
  CACHE_KEYS = {
    top_error_services: "quality_metrics:top_error_services",
    top_slowest_services: "quality_metrics:top_slowest_services",
    daily_stats_summary: "quality_metrics:daily_stats_summary",
    hourly_stats_summary: "quality_metrics:hourly_stats_summary",
    service_health_status: "quality_metrics:service_health_status"
  }.freeze

  CACHE_EXPIRY = {
    standard: 5.minutes,
    extended: 30.minutes
  }.freeze

  # Main perform method
  def perform(options = {})
    # Create audit log entry
    audit_log = ServiceAuditLog.create_for_service(
      SERVICE_NAME,
      operation_type: "refresh_metrics"
    )

    begin
      audit_log.mark_started!
      start_time = Time.current

      # Refresh materialized views
      refresh_materialized_views

      # Cache key metrics in Redis
      cache_key_metrics

      # Check for alerts
      check_for_alerts

      # Mark success in audit log
      execution_time = ((Time.current - start_time) * 1000).round
      audit_log.mark_success!(
        {
          status: "completed",
          execution_time_ms: execution_time,
          refreshed_at: Time.current.iso8601,
          cache_keys_updated: CACHE_KEYS.keys
        },
        [ "daily_service_stats", "hourly_service_stats" ]
      )

      # Log success
      Rails.logger.info "[#{SERVICE_NAME}] Successfully refreshed metrics in #{execution_time}ms"

      true
    rescue StandardError => e
      # Log error details
      error_message = "Failed to refresh quality metrics: #{e.message}"
      Rails.logger.error "[#{SERVICE_NAME}] #{error_message}\n#{e.backtrace.join("\n")}"

      # Mark failure in audit log
      audit_log.mark_failed!(
        error_message,
        {
          error: e.message,
          error_class: e.class.name,
          backtrace: e.backtrace.first(5)
        },
        [ "failed" ]
      )

      # Re-raise the error for Sidekiq retry mechanism
      raise
    end
  end

  private

  # Refresh materialized views
  def refresh_materialized_views
    Rails.logger.info "[#{SERVICE_NAME}] Refreshing materialized views"

    # Measure performance of each refresh
    daily_start = Time.current
    DailyServiceStat.refresh_materialized_view
    daily_time = ((Time.current - daily_start) * 1000).round

    hourly_start = Time.current
    HourlyServiceStat.refresh_materialized_view
    hourly_time = ((Time.current - hourly_start) * 1000).round

    Rails.logger.info "[#{SERVICE_NAME}] Views refreshed - daily: #{daily_time}ms, hourly: #{hourly_time}ms"
  end

  # Cache key metrics in Redis for fast dashboard access
  def cache_key_metrics
    Rails.logger.info "[#{SERVICE_NAME}] Caching key metrics in Redis"

    # Get Redis connection from Rails cache
    redis = Rails.cache.redis

    # Cache top error services (last 24 hours)
    top_error_services = DailyServiceStat.where("date >= ?", 1.day.ago.to_date)
                                        .top_error_services(10)
                                        .map { |stat| serialize_stat(stat) }

    redis.set(
      CACHE_KEYS[:top_error_services],
      top_error_services.to_json,
      ex: CACHE_EXPIRY[:standard]
    )

    # Cache top slowest services (last 24 hours)
    top_slowest_services = DailyServiceStat.where("date >= ?", 1.day.ago.to_date)
                                          .top_slowest_services(10)
                                          .map { |stat| serialize_stat(stat) }

    redis.set(
      CACHE_KEYS[:top_slowest_services],
      top_slowest_services.to_json,
      ex: CACHE_EXPIRY[:standard]
    )

    # Cache daily stats summary
    daily_summary = {
      total_services: DailyServiceStat.today.count("DISTINCT service_name"),
      total_runs: DailyServiceStat.today.sum(:total_runs),
      failed_runs: DailyServiceStat.today.sum(:failed_runs),
      error_rate: calculate_overall_error_rate(DailyServiceStat.today),
      avg_execution_time: DailyServiceStat.today.average(:avg_execution_time_ms).to_f.round(2)
    }

    redis.set(
      CACHE_KEYS[:daily_stats_summary],
      daily_summary.to_json,
      ex: CACHE_EXPIRY[:standard]
    )

    # Cache hourly stats summary
    hourly_summary = {
      total_services: HourlyServiceStat.current_hour.count("DISTINCT service_name"),
      total_runs: HourlyServiceStat.current_hour.sum(:total_runs),
      failed_runs: HourlyServiceStat.current_hour.sum(:failed_runs),
      error_rate: calculate_overall_error_rate(HourlyServiceStat.current_hour),
      avg_execution_time: HourlyServiceStat.current_hour.average(:avg_execution_time_ms).to_f.round(2)
    }

    redis.set(
      CACHE_KEYS[:hourly_stats_summary],
      hourly_summary.to_json,
      ex: CACHE_EXPIRY[:standard]
    )

    # Cache service health status
    cache_service_health_status(redis)

    Rails.logger.info "[#{SERVICE_NAME}] Successfully cached metrics in Redis"
  end

  # Cache health status for all active services
  def cache_service_health_status(redis)
    # Get all active services
    active_services = ServiceConfiguration.where(active: true).pluck(:service_name)

    # Get latest stats for each service
    service_health = {}

    active_services.each do |service_name|
      # Get the most recent daily stat for this service
      latest_stat = DailyServiceStat.for_service(service_name).recent.first

      if latest_stat
        service_health[service_name] = {
          status: latest_stat.status_label,
          status_class: latest_stat.status_class,
          error_rate: latest_stat.error_rate,
          p95_execution_time_ms: latest_stat.p95_execution_time_ms,
          last_run_at: latest_stat.last_run_at&.iso8601,
          total_runs_today: DailyServiceStat.today.for_service(service_name).sum(:total_runs),
          failed_runs_today: DailyServiceStat.today.for_service(service_name).sum(:failed_runs)
        }
      else
        # No stats available
        service_health[service_name] = {
          status: "Unknown",
          status_class: "unknown",
          error_rate: nil,
          p95_execution_time_ms: nil,
          last_run_at: nil,
          total_runs_today: 0,
          failed_runs_today: 0
        }
      end
    end

    redis.set(
      CACHE_KEYS[:service_health_status],
      service_health.to_json,
      ex: CACHE_EXPIRY[:extended]
    )
  end

  # Check for alert conditions and trigger alerts if needed
  def check_for_alerts
    # This will be implemented in task 1.5 when we create the QualityAlert model
    # For now, just log that we would check alerts here
    Rails.logger.info "[#{SERVICE_NAME}] Alert checking would happen here (to be implemented)"
  end

  # Helper to calculate overall error rate from a collection of stats
  def calculate_overall_error_rate(stats)
    total_runs = stats.sum(:total_runs)
    failed_runs = stats.sum(:failed_runs)

    return 0.0 if total_runs.zero?

    (failed_runs.to_f / total_runs * 100).round(2)
  end

  # Helper to serialize a stat object for Redis
  def serialize_stat(stat)
    {
      id: stat.id,
      service_name: stat.service_name,
      date: stat.date.to_s,
      hour: stat.respond_to?(:hour) ? stat.hour : nil,
      total_runs: stat.total_runs,
      successful_runs: stat.successful_runs,
      failed_runs: stat.failed_runs,
      error_rate: stat.error_rate,
      avg_execution_time_ms: stat.avg_execution_time_ms,
      p95_execution_time_ms: stat.p95_execution_time_ms,
      status_class: stat.status_class,
      status_label: stat.status_label
    }
  end
end
