class AddLastFinancialDataFetchAtToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :last_financial_data_fetch_at, :datetime
  end
end
