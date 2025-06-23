class QualityDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_service, only: [ :show, :service_hourly_stats, :service_daily_stats ]
  before_action :check_analyst_role, except: [ :index, :show, :service_hourly_stats, :service_daily_stats ]

  # Redis cache keys - must match those in QualityMetricsWorker
  CACHE_KEYS = {
    top_error_services: "quality_metrics:top_error_services",
    top_slowest_services: "quality_metrics:top_slowest_services",
    daily_stats_summary: "quality_metrics:daily_stats_summary",
    hourly_stats_summary: "quality_metrics:hourly_stats_summary",
    service_health_status: "quality_metrics:service_health_status"
  }.freeze

  # Main dashboard page
  def index
    @page_title = "Service Quality Dashboard"

    # Get overall stats from Redis cache or fallback to DB
    @daily_summary = fetch_from_cache_or_compute(CACHE_KEYS[:daily_stats_summary]) do
      {
        total_services: DailyServiceStat.today.count("DISTINCT service_name"),
        total_runs: DailyServiceStat.today.sum(:total_runs),
        failed_runs: DailyServiceStat.today.sum(:failed_runs),
        error_rate: calculate_overall_error_rate(DailyServiceStat.today),
        avg_execution_time: DailyServiceStat.today.average(:avg_execution_time_ms).to_f.round(2)
      }
    end

    # Get top error services from cache or fallback to DB
    @top_error_services = fetch_from_cache_or_compute(CACHE_KEYS[:top_error_services]) do
      DailyServiceStat.where("date >= ?", 1.day.ago.to_date)
                      .top_error_services(10)
                      .map { |stat| serialize_stat(stat) }
    end

    # Get top slowest services from cache or fallback to DB
    @top_slowest_services = fetch_from_cache_or_compute(CACHE_KEYS[:top_slowest_services]) do
      DailyServiceStat.where("date >= ?", 1.day.ago.to_date)
                      .top_slowest_services(10)
                      .map { |stat| serialize_stat(stat) }
    end

    # Get service health status from cache or fallback to DB
    @service_health = fetch_from_cache_or_compute(CACHE_KEYS[:service_health_status]) do
      compute_service_health_status
    end

    # Get active services
    @active_services = ServiceConfiguration.where(active: true)
                                          .order(:service_name)
                                          .pluck(:service_name)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          daily_summary: @daily_summary,
          top_error_services: @top_error_services,
          top_slowest_services: @top_slowest_services,
          service_health: @service_health
        }
      end
    end
  end

  # Individual service details
  def show
    @page_title = "Service Quality: #{@service_name}"

    # Get daily stats for the service (last 30 days)
    @daily_stats = DailyServiceStat.for_service(@service_name)
                                  .where("date >= ?", 30.days.ago.to_date)
                                  .order(date: :desc)

    # Get hourly stats for the service (last 24 hours)
    @hourly_stats = HourlyServiceStat.for_service(@service_name)
                                    .where("date >= ?", 24.hours.ago.to_date)
                                    .order(date: :desc, hour: :desc)
                                    .limit(24)

    # Get service configuration
    @service_config = ServiceConfiguration.find_by(service_name: @service_name)

    # Get recent audit logs
    @recent_audit_logs = ServiceAuditLog.for_service(@service_name)
                                       .order(created_at: :desc)
                                       .limit(50)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          service_name: @service_name,
          daily_stats: @daily_stats.map { |stat| serialize_stat(stat) },
          hourly_stats: @hourly_stats.map { |stat| serialize_stat(stat) },
          service_config: @service_config.as_json(except: [ :created_at, :updated_at ]),
          recent_audit_logs: @recent_audit_logs.map { |log| serialize_audit_log(log) }
        }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to quality_dashboard_index_path, alert: "Service '#{@service_name}' not found" }
      format.json { render json: { error: "Service not found" }, status: :not_found }
    end
  end

  # API endpoint for service hourly stats (for AJAX charts)
  def service_hourly_stats
    days = params[:days].present? ? params[:days].to_i : 1

    @stats = HourlyServiceStat.for_service(@service_name)
                             .where("date >= ?", days.days.ago.to_date)
                             .order(date: :asc, hour: :asc)

    render json: {
      service_name: @service_name,
      stats: @stats.map { |stat| serialize_stat(stat) }
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # API endpoint for service daily stats (for AJAX charts)
  def service_daily_stats
    days = params[:days].present? ? params[:days].to_i : 30

    @stats = DailyServiceStat.for_service(@service_name)
                            .where("date >= ?", days.days.ago.to_date)
                            .order(date: :asc)

    render json: {
      service_name: @service_name,
      stats: @stats.map { |stat| serialize_stat(stat) }
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # Trigger a refresh of the materialized views
  def refresh_stats
    unless current_user.role == "admin"
      respond_to do |format|
        format.html { redirect_to quality_dashboard_index_path, alert: "You don't have permission to refresh stats" }
        format.json { render json: { error: "Permission denied" }, status: :forbidden }
      end
      return
    end

    begin
      QualityMetricsWorker.perform_later

      respond_to do |format|
        format.html { redirect_to quality_dashboard_index_path, notice: "Stats refresh has been scheduled" }
        format.json { render json: { message: "Stats refresh has been scheduled" } }
      end
    rescue StandardError => e
      respond_to do |format|
        format.html { redirect_to quality_dashboard_index_path, alert: "Failed to schedule stats refresh: #{e.message}" }
        format.json { render json: { error: e.message }, status: :internal_server_error }
      end
    end
  end

  private

  def set_service
    @service_name = params[:id]

    # Verify service exists
    unless ServiceConfiguration.exists?(service_name: @service_name)
      raise ActiveRecord::RecordNotFound, "Service '#{@service_name}' not found"
    end
  end

  def check_analyst_role
    unless current_user.role == "admin" || current_user.role == "analyst"
      respond_to do |format|
        format.html { redirect_to quality_dashboard_index_path, alert: "You don't have permission to access this page" }
        format.json { render json: { error: "Permission denied" }, status: :forbidden }
      end
    end
  end

  # Fetch data from Redis cache or compute it if not available
  def fetch_from_cache_or_compute(cache_key)
    # Try to get from Redis
    cached_data = Rails.cache.redis.get(cache_key)

    if cached_data.present?
      # Parse JSON from cache
      begin
        return JSON.parse(cached_data, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse cached data for #{cache_key}: #{e.message}"
      end
    end

    # Cache miss or parse error, compute the data
    computed_data = yield

    # Cache the computed data (5 minute expiry)
    begin
      Rails.cache.redis.set(cache_key, computed_data.to_json, ex: 5.minutes.to_i)
    rescue StandardError => e
      Rails.logger.error "Failed to cache data for #{cache_key}: #{e.message}"
    end

    computed_data
  end

  # Compute service health status for all active services
  def compute_service_health_status
    active_services = ServiceConfiguration.where(active: true).pluck(:service_name)
    service_health = {}

    active_services.each do |service_name|
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

    service_health
  end

  # Calculate overall error rate from a collection of stats
  def calculate_overall_error_rate(stats)
    total_runs = stats.sum(:total_runs)
    failed_runs = stats.sum(:failed_runs)

    return 0.0 if total_runs.zero?

    (failed_runs.to_f / total_runs * 100).round(2)
  end

  # Serialize a stat object for JSON response
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

  # Serialize an audit log for JSON response
  def serialize_audit_log(log)
    {
      id: log.id,
      service_name: log.service_name,
      operation_type: log.operation_type,
      status: log.status,
      created_at: log.created_at.iso8601,
      started_at: log.started_at&.iso8601,
      completed_at: log.completed_at&.iso8601,
      execution_time_ms: log.execution_time_ms,
      error_message: log.error_message,
      record_id: log.record_id,
      table_name: log.table_name
    }
  end
end
