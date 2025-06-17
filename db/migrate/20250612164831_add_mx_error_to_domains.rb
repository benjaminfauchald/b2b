class AddMxErrorToDomains < ActiveRecord::Migration[8.0]
  def change
    add_column :domains, :mx_error, :string
  end
end 