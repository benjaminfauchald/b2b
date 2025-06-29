require 'firecrawl'

puts "Testing final Firecrawl setup..."
puts "API key present: #{ENV['FIRECRAWL_API_KEY'].present?}"

begin
  # Set API key
  Firecrawl.api_key ENV['FIRECRAWL_API_KEY']

  # Test with a simple, fast-loading site first
  puts "\nTesting with simple site..."
  response = Firecrawl.scrape("https://example.com")
  puts "Response success: #{response.success?}"

  if response.success?
    puts "Title: #{response.result.metadata['title']}"
    puts "Content length: #{response.result.markdown.length}"
    puts "Screenshot URL: #{response.result.screenshot_url}"
  else
    puts "Error: #{response.result.error_description}"
  end

rescue => e
  puts "Error: #{e.message}"
  puts "Error class: #{e.class}"
end
