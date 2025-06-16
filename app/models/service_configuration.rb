class ServiceConfiguration < ApplicationRecord
  self.primary_key = 'service_name'

  has_many :service_audit_logs, foreign_key: 'service_name', primary_key: 'service_name'
  has_many :service_performance_stats, foreign_key: 'service_name', primary_key: 'service_name'
  has_many :latest_service_runs, foreign_key: 'service_name', primary_key: 'service_name'
  has_many :records_needing_refresh, foreign_key: 'service_name', primary_key: 'service_name'

  # Validations
  validates :service_name, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :refresh_interval_hours, presence: true, numericality: { greater_than: 0 }
  validates :batch_size, numericality: { greater_than: 0 }
  validates :retry_attempts, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :frequent_refresh, ->(hours) { where('refresh_interval_hours < ?', hours) }

  # Class methods
  def self.active?(service_name)
    find_by(service_name: service_name)&.active?
  end

  def self.find_or_create_by_service_name(service_name, attributes = {})
    find_or_create_by(service_name: service_name) do |config|
      config.assign_attributes(attributes)
    end
  end

  def self.enable_service(service_name)
    find_or_create_by_service_name(service_name).update(active: true)
  end

  def self.disable_service(service_name)
    find_or_create_by_service_name(service_name).update(active: false)
  end

  def self.set_refresh_interval(service_name, hours)
    find_or_create_by_service_name(service_name).update(refresh_interval_hours: hours)
  end

  # Instance methods
  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end

  def add_dependency(service_name)
    return if depends_on_services.include?(service_name)
    
    self.depends_on_services = (depends_on_services || []) + [service_name]
    save!
  end

  def remove_dependency(service_name)
    self.depends_on_services = (depends_on_services || []) - [service_name]
    save!
  end

  def update_setting(key, value)
    self.settings = (settings || {}).merge(key.to_s => value)
    save!
  end

  def get_setting(key, default_value = nil)
    (settings || {})[key.to_s] || default_value
  end

  def needs_refresh?(last_run_time)
    return true if last_run_time.nil?
    
    last_run_time < refresh_interval_hours.hours.ago
  end

  def dependencies_met?
    return true if depends_on_services.blank?
    
    dependency_configs = ServiceConfiguration.where(service_name: depends_on_services)
    dependency_configs.all?(&:active?)
  end

  # Class methods
  def self.for_service(service_name)
    return nil if service_name.blank?
    find_by(service_name: service_name)
  end

  def self.create_default(service_name, **overrides)
    create!({
      service_name: service_name,
      refresh_interval_hours: 720,
      active: true,
      batch_size: 1000,
      retry_attempts: 3,
      depends_on_services: [],
      settings: {}
    }.merge(overrides))
  end

  def self.bulk_update_settings(service_settings_hash)
    service_settings_hash.each do |service_name, settings|
      config = for_service(service_name)
      next unless config
      
      settings.each do |key, value|
        config.update_setting(key, value)
      end
    end
  end

  def performance_stats
    ServicePerformanceStat.find_by_service_name(service_name)
  end

  def latest_runs
    LatestServiceRun.where(service_name: service_name)
  end

  def records_needing_refresh
    RecordsNeedingRefresh.where(service_name: service_name)
  end

  def audit_logs
    service_audit_logs
  end

  def success_rate
    stats = performance_stats
    stats&.success_rate
  end

  def failure_rate
    stats = performance_stats
    stats&.failure_rate
  end

  def health_status
    stats = performance_stats
    stats&.health_status
  end

  def healthy?
    health_status == 'healthy'
  end

  def needs_attention?
    health_status == 'needs_attention'
  end

  def critical?
    health_status == 'critical'
  end

  private

  # Callbacks
  after_create :log_creation
  after_update :log_update

  def log_creation
    Rails.logger.info "Service configuration created for #{service_name}"
  end

  def log_update
    Rails.logger.info "Service configuration updated for #{service_name}"
  end
end 