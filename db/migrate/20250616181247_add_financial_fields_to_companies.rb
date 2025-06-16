class AddFinancialFieldsToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :revenue, :decimal
    add_column :companies, :profit, :decimal
    add_column :companies, :equity, :decimal
    add_column :companies, :total_assets, :decimal
    add_column :companies, :current_assets, :decimal
    add_column :companies, :fixed_assets, :decimal
    add_column :companies, :current_liabilities, :decimal
    add_column :companies, :long_term_liabilities, :decimal
    add_column :companies, :year, :integer
  end
end
