class AddIndexToCompaniesSourceCountry < ActiveRecord::Migration[8.0]
  def change
    add_index :companies, :source_country
    
    # Also add a composite index for country + revenue filtering
    # This will optimize queries like: WHERE source_country = 'NO' AND operating_revenue > 10000000
    add_index :companies, [:source_country, :operating_revenue]
    
    # Add index for country + website filtering
    # This will optimize queries for web discovery by country
    add_index :companies, [:source_country, :website]
  end
end
