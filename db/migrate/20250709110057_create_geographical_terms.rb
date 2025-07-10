class CreateGeographicalTerms < ActiveRecord::Migration[8.0]
  def change
    create_table :geographical_terms do |t|
      t.string :term, null: false
      t.string :term_type, null: false
      t.string :language, null: false, default: 'NO'

      t.timestamps
    end
    
    add_index :geographical_terms, :term
    add_index :geographical_terms, :term_type
    add_index :geographical_terms, :language
    add_index :geographical_terms, [:term, :language], unique: true
  end
end
