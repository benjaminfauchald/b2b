class AddImportTagToPeople < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :import_tag, :string
    add_index :people, :import_tag
  end
end
