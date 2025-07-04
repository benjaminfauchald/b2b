class AddUniqueConstraintsToPeople < ActiveRecord::Migration[8.0]
  def change
    # Remove existing index on profile_url if it exists (it was uniqueness: { allow_blank: true })
    remove_index :people, :profile_url if index_exists?(:people, :profile_url)

    # Add unique indexes for email and profile_url (LinkedIn)
    # Using partial indexes to allow NULLs but ensure uniqueness of non-NULL values
    add_index :people, :email, unique: true, where: "email IS NOT NULL AND email != ''"
    add_index :people, :profile_url, unique: true, where: "profile_url IS NOT NULL AND profile_url != ''"
  end
end
