class AddEmailValidationFieldsToPeople < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :email_validation_engine, :string
    add_column :people, :email_validation_details, :jsonb, default: {}
    
    # Add index for email validation engine for performance
    add_index :people, :email_validation_engine
    
    # Add GIN index for JSONB email validation details
    add_index :people, :email_validation_details, using: :gin
  end
end
