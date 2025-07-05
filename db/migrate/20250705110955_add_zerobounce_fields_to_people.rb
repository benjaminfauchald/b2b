class AddZerobounceFieldsToPeople < ActiveRecord::Migration[8.0]
  def change
    # ZeroBounce core verification fields
    add_column :people, :zerobounce_status, :string
    add_column :people, :zerobounce_sub_status, :string
    add_column :people, :zerobounce_account, :string
    add_column :people, :zerobounce_domain, :string

    # ZeroBounce extracted information
    add_column :people, :zerobounce_first_name, :string
    add_column :people, :zerobounce_last_name, :string
    add_column :people, :zerobounce_gender, :string

    # ZeroBounce technical validation
    add_column :people, :zerobounce_free_email, :boolean
    add_column :people, :zerobounce_mx_found, :boolean
    add_column :people, :zerobounce_mx_record, :string
    add_column :people, :zerobounce_smtp_provider, :string
    add_column :people, :zerobounce_did_you_mean, :string

    # ZeroBounce activity data
    add_column :people, :zerobounce_last_known_activity, :timestamp
    add_column :people, :zerobounce_activity_data_count, :integer
    add_column :people, :zerobounce_activity_data_types, :text
    add_column :people, :zerobounce_activity_data_channels, :text

    # ZeroBounce quality score and tracking
    add_column :people, :zerobounce_quality_score, :decimal, precision: 5, scale: 2
    add_column :people, :zerobounce_imported_at, :timestamp

    # Add indexes for key comparison fields
    add_index :people, :zerobounce_status
    add_index :people, :zerobounce_quality_score
    add_index :people, :zerobounce_imported_at
  end
end
