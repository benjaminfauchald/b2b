class AddEnhancementFieldsToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Financial data service fields
    add_column :companies, :financial_data_updated_at, :datetime

    # Web discovery service fields
    add_column :companies, :web_pages, :jsonb
    add_column :companies, :web_discovery_updated_at, :datetime

    # Employee discovery service fields
    add_column :companies, :employees_data, :jsonb
    add_column :companies, :employee_discovery_updated_at, :datetime

    # Add indexes for better query performance
    add_index :companies, :financial_data_updated_at
    add_index :companies, :web_discovery_updated_at
    add_index :companies, :linkedin_last_processed_at
    add_index :companies, :employee_discovery_updated_at
    add_index :companies, :web_pages, using: :gin
    add_index :companies, :employees_data, using: :gin
  end
end
