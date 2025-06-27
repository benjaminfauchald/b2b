require 'firecrawl'

puts "Testing simple Firecrawl call..."
puts "API key present: #{ENV['FIRECRAWL_API_KEY'].present?}"

begin
  # Try the simplest possible call
  puts "\nTrying Firecrawl.scrape with just URL..."
  response = Firecrawl.scrape("https://itavisen.no")
  puts "Response class: #{response.class}"
  puts "Response: #{response}"
  
rescue => e
  puts "Error: #{e.message}"
  puts "Error class: #{e.class}"
end

begin
  # Try with API key as parameter
  puts "\nTrying with API key parameter..."
  response = Firecrawl.scrape("https://itavisen.no", ENV['FIRECRAWL_API_KEY'])
  puts "Response class: #{response.class}"
  puts "Response: #{response}"
  
rescue => e
  puts "Error: #{e.message}"
  puts "Error class: #{e.class}"
end