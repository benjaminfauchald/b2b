class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies do |t|
      # Core Identity
      t.string :source_country, null: false, limit: 2
      t.string :source_registry, null: false, limit: 20
      t.text :source_id, null: false
      t.text :registration_number, null: false
      t.text :company_name, null: false

      # Organization Structure
      t.text :organization_form_code
      t.text :organization_form_description
      t.date :registration_date
      t.date :deregistration_date
      t.text :deregistration_reason
      t.text :registration_country

      # Industry Classification
      t.text :primary_industry_code
      t.text :primary_industry_description
      t.text :secondary_industry_code
      t.text :secondary_industry_description
      t.text :tertiary_industry_code
      t.text :tertiary_industry_description
      t.text :business_description
      t.text :segment
      t.text :industry

      # Employee Information
      t.boolean :has_registered_employees
      t.integer :employee_count
      t.date :employee_registration_date_registry
      t.date :employee_registration_date_nav
      t.integer :linkedin_employee_count

      # Contact Information
      t.text :website
      t.text :email
      t.text :phone
      t.text :mobile

      # Postal Address
      t.text :postal_address
      t.text :postal_city
      t.text :postal_code
      t.text :postal_municipality
      t.text :postal_municipality_code
      t.text :postal_country
      t.text :postal_country_code

      # Business Address
      t.text :business_address
      t.text :business_city
      t.text :business_postal_code
      t.text :business_municipality
      t.text :business_municipality_code
      t.text :business_country
      t.text :business_country_code

      # Financial Information
      t.integer :last_submitted_annual_report
      t.bigint :ordinary_result
      t.bigint :annual_result
      t.bigint :operating_revenue
      t.bigint :operating_costs

      # LinkedIn Integration
      t.text :linkedin_url
      t.text :linkedin_ai_url
      t.text :linkedin_alt_url
      t.jsonb :linkedin_alternatives
      t.boolean :linkedin_processed, default: false
      t.datetime :linkedin_last_processed_at
      t.integer :linkedin_ai_confidence

      # Search/Matching Fields
      t.text :sps_match
      t.text :sps_match_percentage
      t.integer :http_error
      t.text :http_error_message

      # System Fields
      t.jsonb :source_raw_data
      t.integer :brreg_id
      t.string :country, limit: 2
      t.text :description

      t.timestamps
    end

    # Add indexes for performance
    add_index :companies, :operating_revenue
    add_index :companies, :linkedin_ai_url
    add_index :companies, [ :source_country, :source_registry ]
    add_index :companies, :organization_form_description
  end
end
