class AddEnhancementFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email_provider, :string
    add_column :users, :last_enhanced_at, :datetime
  end
end
