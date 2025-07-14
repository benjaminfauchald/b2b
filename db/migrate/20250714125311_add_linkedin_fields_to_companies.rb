class AddLinkedinFieldsToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :linkedin_slug, :string
    add_index :companies, :linkedin_slug, unique: true
  end
end
