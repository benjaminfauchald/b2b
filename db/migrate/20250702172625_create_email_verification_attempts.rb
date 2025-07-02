class CreateEmailVerificationAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :email_verification_attempts do |t|
      t.references :person, null: false, foreign_key: true
      t.string :email
      t.string :domain
      t.string :status
      t.integer :response_code
      t.text :response_message
      t.datetime :attempted_at

      t.timestamps
    end
  end
end
