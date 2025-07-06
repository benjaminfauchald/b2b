class AddLinkedinInternalFieldsToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :linkedin_internal_processed, :boolean, default: false
    add_column :companies, :linkedin_internal_last_processed_at, :datetime
    add_column :companies, :linkedin_internal_sales_navigator_url, :text
    add_column :companies, :linkedin_internal_profile_count, :integer
    add_column :companies, :linkedin_internal_error_message, :text
    
    # Add indexes for querying
    add_index :companies, :linkedin_internal_processed
    add_index :companies, :linkedin_internal_last_processed_at
  end
end