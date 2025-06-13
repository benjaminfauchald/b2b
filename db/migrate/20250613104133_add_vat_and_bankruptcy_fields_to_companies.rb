class AddVatAndBankruptcyFieldsToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :vat_registered, :boolean
    add_column :companies, :vat_registration_date, :date
    add_column :companies, :voluntary_vat_registered, :boolean
    add_column :companies, :voluntary_vat_registration_date, :date
    add_column :companies, :bankruptcy, :boolean
    add_column :companies, :bankruptcy_date, :date
    add_column :companies, :under_liquidation, :boolean
    add_column :companies, :liquidation_date, :date
  end
end
