class AddIndexToPersonProfileUrl < ActiveRecord::Migration[8.0]
  def change
    add_index :people, :profile_url, unique: true unless index_exists?(:people, :profile_url)
  end
end
