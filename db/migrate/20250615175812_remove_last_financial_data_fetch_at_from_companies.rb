class RemoveLastFinancialDataFetchAtFromCompanies < ActiveRecord::Migration[8.0]
  def change
    remove_column :companies, :last_financial_data_fetch_at, :datetime
  end
end
