class CreateServiceConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :service_configurations do |t|
      # Unique service identifier
      t.string :service_name, null: false, limit: 100

      # Service scheduling and refresh settings
      t.integer :refresh_interval_hours, default: 720 # 30 days

      # Service dependencies
      t.text :depends_on_services, array: true, default: []

      # Service control flags
      t.boolean :active, default: true, null: false

      # Processing configuration
      t.integer :batch_size, default: 1000
      t.integer :retry_attempts, default: 3

      # Flexible settings storage
      t.jsonb :settings, default: {}

      t.timestamps
    end

    # Ensure unique service names
    add_index :service_configurations, :service_name, unique: true

    # Index for active services
    add_index :service_configurations, :active

    # JSONB index for settings queries
    add_index :service_configurations, :settings, using: :gin
  end
end
