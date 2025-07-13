class AddPhantomBusterFieldsToPeople < ActiveRecord::Migration[8.0]
  def change
    # Name fields
    add_column :people, :first_name, :string
    add_column :people, :last_name, :string
    
    # Company fields
    add_column :people, :company_url, :string
    add_column :people, :regular_company_url, :string
    add_column :people, :industry, :string
    add_column :people, :company_location, :string
    add_column :people, :phantom_buster_company_id, :string
    
    # Experience fields
    add_column :people, :title_description, :text
    add_column :people, :duration_in_role, :string
    add_column :people, :duration_in_company, :string
    
    # Past experience fields
    add_column :people, :past_experience_company_name, :string
    add_column :people, :past_experience_company_url, :string
    add_column :people, :past_experience_company_title, :string
    add_column :people, :past_experience_date, :string
    add_column :people, :past_experience_duration, :string
    
    # LinkedIn metadata
    add_column :people, :shared_connections_count, :integer
    add_column :people, :vmid, :string
    add_column :people, :is_premium, :boolean, default: false
    add_column :people, :is_open_link, :boolean, default: false
    add_column :people, :default_profile_url, :string
    
    # Import tracking
    add_column :people, :query, :string
    add_column :people, :phantom_buster_timestamp, :datetime
    
    # Add indexes for performance
    add_index :people, :phantom_buster_company_id
    add_index :people, :vmid
    add_index :people, :is_premium
    add_index :people, :phantom_buster_timestamp
  end
end