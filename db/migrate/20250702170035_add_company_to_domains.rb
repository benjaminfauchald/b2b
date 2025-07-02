class AddCompanyToDomains < ActiveRecord::Migration[8.0]
  def change
    add_reference :domains, :company, null: true, foreign_key: true
    add_index :domains, [ :company_id, :domain ], unique: true
  end
end
