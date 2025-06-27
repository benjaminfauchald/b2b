domain = Domain.find(27)
puts "Domain: #{domain.domain}"
puts "Web Content Data present: #{domain.web_content_data.present?}"

if domain.web_content_data.present?
  puts "Web content extracted successfully!"
  puts "Content preview: #{domain.web_content_data.to_s[0..200]}..."
else
  puts "Web content data still not present"
end

puts ""
puts "Latest audit log:"
latest_log = domain.service_audit_logs.where(service_name: "domain_web_content_extraction").order(created_at: :desc).first
if latest_log
  puts "  Status: #{latest_log.status}"
  puts "  Created: #{latest_log.created_at}"
  puts "  Completed: #{latest_log.completed_at}"
  puts "  Metadata: #{latest_log.metadata}"
else
  puts "  No audit logs found"
end