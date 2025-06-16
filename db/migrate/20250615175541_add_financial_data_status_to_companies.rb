class AddFinancialDataStatusToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :financial_data_status, :string
  end
end
