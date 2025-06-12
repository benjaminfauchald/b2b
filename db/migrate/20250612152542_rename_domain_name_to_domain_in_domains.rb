class RenameDomainNameToDomainInDomains < ActiveRecord::Migration[8.0]
  def change
    rename_column :domains, :domain_name, :domain
  end
end
