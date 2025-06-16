class RecordsNeedingRefresh < ApplicationRecord
  self.table_name = 'records_needing_refresh'
  self.primary_key = ['service_name', 'auditable_type', 'auditable_id']

  belongs_to :auditable, polymorphic: true
  belongs_to :service_configuration, foreign_key: 'service_name', primary_key: 'service_name'

  def self.refresh
    connection.execute('REFRESH MATERIALIZED VIEW records_needing_refresh')
  end

  def self.find_by_auditable(service_name, auditable)
    find_by(
      service_name: service_name,
      auditable_type: auditable.class.name,
      auditable_id: auditable.id
    )
  end

  def needs_refresh?
    needs_refresh
  end

  def last_run_at
    completed_at
  end

  def time_since_last_run
    return nil unless last_run_at
    Time.current - last_run_at
  end

  def hours_since_last_run
    return nil unless time_since_last_run
    (time_since_last_run / 3600).round(2)
  end
end 