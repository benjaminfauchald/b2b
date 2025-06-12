class AddDomainToDomains < ActiveRecord::Migration[8.0]
  def change
    add_column :domains, :domain, :boolean
  end
end
