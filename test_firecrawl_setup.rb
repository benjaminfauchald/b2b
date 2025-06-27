require 'firecrawl'

puts "Testing Firecrawl setup patterns..."

# Try setting the global API key
Firecrawl.api_key = ENV['FIRECRAWL_API_KEY']
puts "Set global API key: #{Firecrawl.api_key.present?}"

begin
  url = "https://itavisen.no"
  puts "Testing scrape of #{url}..."
  
  response = Firecrawl.scrape(url)
  puts "Response class: #{response.class}"
  puts "Response keys: #{response.keys}" if response.respond_to?(:keys)
  puts "Success: #{response['success']}" if response.is_a?(Hash)
  
rescue => e
  puts "Error: #{e.message}"
  puts "Error class: #{e.class}"
end