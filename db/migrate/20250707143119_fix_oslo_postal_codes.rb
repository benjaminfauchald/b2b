class FixOsloPostalCodes < ActiveRecord::Migration[8.0]
  def up
    # Fix all 3-digit postal codes in Oslo by adding leading zero
    say "Fixing Oslo postal codes..."
    
    # Count companies that need fixing
    count = Company.where(postal_city: 'OSLO').where("LENGTH(postal_code) = 3").count
    say "Found #{count} companies with 3-digit postal codes in Oslo"
    
    # Update in batches to avoid locking the table for too long
    Company.where(postal_city: 'OSLO')
           .where("LENGTH(postal_code) = 3")
           .in_batches(of: 1000) do |batch|
      batch.update_all("postal_code = CONCAT('0', postal_code)")
    end
    
    say "Fixed #{count} postal codes in Oslo"
  end

  def down
    # Reverse the operation - remove leading zeros from Oslo postal codes
    say "Reversing Oslo postal code fixes..."
    
    # Count companies that need reversing
    count = Company.where(postal_city: 'OSLO')
                   .where("LENGTH(postal_code) = 4")
                   .where("postal_code LIKE '0%'")
                   .count
    say "Found #{count} companies with 4-digit postal codes starting with 0 in Oslo"
    
    # Update in batches to avoid locking the table for too long
    Company.where(postal_city: 'OSLO')
           .where("LENGTH(postal_code) = 4")
           .where("postal_code LIKE '0%'")
           .in_batches(of: 1000) do |batch|
      batch.update_all("postal_code = SUBSTRING(postal_code, 2)")
    end
    
    say "Reversed #{count} postal codes in Oslo"
  end
end
