class CreateEmailVerificationAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :email_verification_attempts do |t|
      t.references :person, null: false, foreign_key: true
      t.string :email, null: false
      t.string :domain, null: false
      t.string :status, null: false
      t.integer :response_code
      t.text :response_message
      t.datetime :attempted_at, null: false

      t.timestamps
    end

    add_index :email_verification_attempts, :email
    add_index :email_verification_attempts, :domain
    add_index :email_verification_attempts, :attempted_at
  end
end
