class CreateLinkedinCompanyLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :linkedin_company_lookups do |t|
      t.string :linkedin_company_id, null: false
      t.references :company, null: false, foreign_key: true
      t.string :linkedin_slug
      t.integer :confidence_score, default: 100
      t.datetime :last_verified_at

      t.timestamps
    end
    
    add_index :linkedin_company_lookups, :linkedin_company_id, unique: true
    add_index :linkedin_company_lookups, :linkedin_slug
    add_index :linkedin_company_lookups, :last_verified_at
  end
end
