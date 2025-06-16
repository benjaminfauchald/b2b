class RemoveFinancialDataStatusFromCompanies < ActiveRecord::Migration[8.0]
  def change
    remove_column :companies, :financial_data_status, :string
  end
end
