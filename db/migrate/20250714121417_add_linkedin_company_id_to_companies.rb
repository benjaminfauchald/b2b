class AddLinkedinCompanyIdToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :linkedin_company_id, :bigint
    add_index :companies, :linkedin_company_id, unique: true
  end
end
