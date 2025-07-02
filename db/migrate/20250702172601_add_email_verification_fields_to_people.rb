class AddEmailVerificationFieldsToPeople < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :email_verification_status, :string, default: 'unverified'
    add_column :people, :email_verification_confidence, :float, default: 0.0
    add_column :people, :email_verification_checked_at, :datetime
    add_column :people, :email_verification_metadata, :jsonb, default: {}

    add_index :people, :email_verification_status
    add_index :people, :email_verification_checked_at
  end
end
