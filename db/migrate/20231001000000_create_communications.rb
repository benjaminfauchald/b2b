class CreateCommunications < ActiveRecord::Migration[7.0]
  def change
    create_table :communications do |t|
      t.datetime :timestamp
      t.string :event_type
      t.string :campaign_name
      t.string :workspace
      t.string :campaign_id
      t.string :service
      t.string :connection_attempt_type
      t.string :lead_email
      t.string :first_name
      t.string :last_name
      t.string :company_name
      t.string :website
      t.string :phone
      t.integer :step
      t.string :email_account
      t.timestamps
    end
  end
end
