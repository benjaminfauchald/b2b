class AddDnsToDomains < ActiveRecord::Migration[8.0]
  def change
    add_column :domains, :dns, :boolean
  end
end
