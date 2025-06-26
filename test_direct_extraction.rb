puts "Testing direct web content extraction for domain 27..."

domain = Domain.find(27)
puts "Domain: #{domain.domain} (#{domain.a_record_ip})"

# Test the service directly with force flag
service = DomainWebContentExtractionService.new(domain: domain, force: true)
result = service.perform

puts "\nService result:"
puts "  Success: #{result.success?}"
puts "  Message: #{result.message}" if result.respond_to?(:message) && result.message
puts "  Error: #{result.error}" if result.respond_to?(:error) && result.error

if result.success? && result.respond_to?(:data) && result.data
  puts "  Data keys: #{result.data.keys}" if result.data.respond_to?(:keys)
end

# Check if domain was updated
domain.reload
puts "\nDomain after extraction:"
puts "  Web content data present: #{domain.web_content_data.present?}"
if domain.web_content_data.present?
  puts "  Title: #{domain.web_content_data['title']}"
  puts "  Content length: #{domain.web_content_data['content']&.length || 0}"
end