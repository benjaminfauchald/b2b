class AddUniqueIndexToCompaniesRegistrationNumber < ActiveRecord::Migration[8.0]
  def change
    # Add a unique index on registration_number
    add_index :companies, :registration_number, unique: true, name: 'index_companies_on_registration_number_unique'
    
    # If you want to handle potential duplicates during the migration, you can add this:
    # remove_duplicates_up
  end
  
  # This method handles existing duplicates by keeping the most recent record
  # def remove_duplicates_up
  #   # Find all registration numbers that have duplicates
  #   duplicate_numbers = Company
  #     .group(:registration_number)
  #     .having('COUNT(*) > 1')
  #     .pluck(:registration_number)
  #   
  #   duplicate_numbers.each do |number|
  #     # Keep the most recently updated record
  #     records = Company.where(registration_number: number).order(updated_at: :desc)
  #     keeper = records.first
  #     
  #     # Delete all other duplicates
  #     records.where.not(id: keeper.id).delete_all
  #   end
  # end
  # 
  # def remove_duplicates_down
  #   # No need to do anything when rolling back
  # end
end
