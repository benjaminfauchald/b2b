class AddProfileDataToPeople < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :profile_data, :jsonb
    add_column :people, :email_data, :jsonb
  end
end
