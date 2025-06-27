domain = Domain.find(27)
puts "Testing web content extraction service for #{domain.domain}"

# Check prerequisites
puts "Domain has www: #{domain.www}"
puts "Domain has A record IP: #{domain.a_record_ip.present?} (#{domain.a_record_ip})"

# Check if service is active
service_config = ServiceConfiguration.find_by(service_name: "domain_web_content_extraction")
puts "Service config exists: #{service_config.present?}"
puts "Service active: #{service_config&.active?}" if service_config

# Check Firecrawl API key
puts "Firecrawl API key configured: #{ENV['FIRECRAWL_API_KEY'].present?}"

# Test the service
begin
  puts "\nRunning DomainWebContentExtractionService..."
  service = DomainWebContentExtractionService.new(domain: domain)
  result = service.perform
  
  puts "Service result:"
  puts "  Success: #{result.success?}"
  puts "  Message: #{result.message}" if result.respond_to?(:message)
  puts "  Error: #{result.error}" if result.respond_to?(:error)
  puts "  Data keys: #{result.data.keys}" if result.respond_to?(:data) && result.data.respond_to?(:keys)
  
rescue => e
  puts "Service failed with exception: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
end