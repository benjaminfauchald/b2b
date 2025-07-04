class MarkExistingValidEmailsForRevalidation < ActiveRecord::Migration[8.0]
  def up
    # Mark all currently "valid" emails as needing re-validation due to false positive issues
    # Track original status in metadata for analysis
    result = execute <<~SQL
      UPDATE people 
      SET 
        email_verification_status = 'needs_revalidation',
        email_verification_metadata = COALESCE(email_verification_metadata, '{}') || 
          '{"revalidation_reason": "false_positive_cleanup", "original_status": "valid", "marked_at": "#{Time.current.iso8601}"}'
      WHERE email_verification_status = 'valid'
    SQL
    
    # Count how many records were affected
    count = execute("SELECT COUNT(*) FROM people WHERE email_verification_status = 'needs_revalidation' AND email_verification_metadata->>'revalidation_reason' = 'false_positive_cleanup'").first['count']
    puts "Marked #{count} emails with 'valid' status for re-validation due to false positive issues"
  end
  
  def down
    # Restore original valid status (though this may reintroduce false positives)
    execute <<~SQL
      UPDATE people 
      SET email_verification_status = 'valid'
      WHERE email_verification_status = 'needs_revalidation' 
        AND email_verification_metadata->>'revalidation_reason' = 'false_positive_cleanup'
    SQL
  end
end
