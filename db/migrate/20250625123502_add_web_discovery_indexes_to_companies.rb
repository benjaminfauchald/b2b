class AddWebDiscoveryIndexesToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Add composite index for web discovery candidates
    # This index will be used for companies with revenue > 10M and no website
    add_index :companies, [ :operating_revenue, :website ],
              name: 'index_companies_web_discovery_candidates',
              where: "operating_revenue > 10000000 AND (website IS NULL OR website = '')"

    # Add index for web discovery updated timestamp for efficient filtering
    add_index :companies, :web_discovery_updated_at,
              name: 'index_companies_on_web_discovery_updated_at' unless index_exists?(:companies, :web_discovery_updated_at)

    # Add partial index for companies needing web discovery
    add_index :companies, :id,
              name: 'index_companies_needing_web_discovery',
              where: "operating_revenue > 10000000 AND (website IS NULL OR website = '') AND (web_pages IS NULL OR web_pages = '{}' OR jsonb_array_length(web_pages) = 0)"
  end
end
