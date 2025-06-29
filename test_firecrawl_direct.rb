require 'firecrawl'

puts "Testing Firecrawl gem directly..."
puts "Firecrawl API key: #{ENV['FIRECRAWL_API_KEY'].present?}"

begin
  # Try different initialization patterns
  puts "\nTrying Firecrawl::Client.new..."
  client = Firecrawl::Client.new(ENV['FIRECRAWL_API_KEY'])
  puts "Client created successfully: #{client.class}"

rescue NameError => e
  puts "NameError: #{e.message}"

  puts "\nTrying alternative patterns..."
  # Check what's available in the Firecrawl module
  puts "Firecrawl constants: #{Firecrawl.constants}" if defined?(Firecrawl)

rescue => e
  puts "Other error: #{e.message}"
end

# Let's see what's actually available
puts "\nFirecrawl module methods:"
puts Firecrawl.methods.grep(/scrape|client/i) if defined?(Firecrawl)
