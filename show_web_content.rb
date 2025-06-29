domain = Domain.find(27)
puts "Domain: #{domain.domain}"
puts "=" * 50

if domain.web_content_data.present?
  content_data = domain.web_content_data

  puts "TITLE:"
  puts content_data['title']
  puts

  puts "URL:"
  puts content_data['url']
  puts

  puts "EXTRACTED AT:"
  puts content_data['extracted_at']
  puts

  puts "SCREENSHOT URL:"
  puts content_data['screenshot_url'] || 'None'
  puts

  puts "CONTENT (#{content_data['content']&.length || 0} characters):"
  puts "-" * 50
  puts content_data['content']
  puts "-" * 50
else
  puts "No web content data found"
end
