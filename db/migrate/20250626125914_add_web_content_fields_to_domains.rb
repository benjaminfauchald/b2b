class AddWebContentFieldsToDomains < ActiveRecord::Migration[8.0]
  def change
    add_column :domains, :a_record_ip, :string
    add_column :domains, :web_content_data, :jsonb
    
    # Add indexes for better query performance
    add_index :domains, :a_record_ip
    add_index :domains, :web_content_data, using: :gin
  end
end
