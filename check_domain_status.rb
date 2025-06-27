domain = Domain.find(27)
puts "Domain: #{domain.domain}"
puts "Web content data present: #{domain.web_content_data.present?}"
puts "Last audit logs:"
domain.service_audit_logs
  .where(service_name: "domain_web_content_extraction")
  .order(created_at: :desc)
  .limit(3)
  .each do |log|
    puts "  #{log.created_at} - #{log.status} - #{log.metadata&.[]('error') || 'success'}"
  end