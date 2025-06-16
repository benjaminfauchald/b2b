class AddFinancialDataToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :financial_data, :text
  end
end
