class AddEnhancementFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email_provider, :string
    add_column :users, :last_enhanced_at, :datetime
    add_column :users, :enhanced, :boolean, default: false, null: false
  end
end
