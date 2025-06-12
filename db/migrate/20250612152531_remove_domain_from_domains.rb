class RemoveDomainFromDomains < ActiveRecord::Migration[8.0]
  def change
    remove_column :domains, :domain, :boolean
  end
end
