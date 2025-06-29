domain = Domain.find(27)
puts "Domain: #{domain.domain}"
puts "Web content data: #{domain.web_content_data.present?}"

if domain.web_content_data.present?
  puts "\nWeb Content Data:"
  puts "  Title: #{domain.web_content_data['title']}"
  puts "  Content length: #{domain.web_content_data['content']&.length || 0} characters"
  puts "  Screenshot URL: #{domain.web_content_data['screenshot_url']}"
  puts "  Extracted at: #{domain.web_content_data['extracted_at']}"
else
  puts "\nNo web content data found"
end

puts "\nRecent audit logs (last 5):"
domain.service_audit_logs
  .where(service_name: "domain_web_content_extraction")
  .order(created_at: :desc)
  .limit(5)
  .each do |log|
    metadata = log.metadata || {}
    puts "  #{log.created_at} - #{log.status}"
    puts "    Error: #{metadata['error']}" if metadata['error']
    puts "    URL: #{metadata['url']}" if metadata['url']
    puts "    Success: #{metadata['extraction_success']}" if metadata.key?('extraction_success')
  end

# Check if there are any pending Sidekiq jobs
puts "\nChecking background jobs..."
begin
  require 'sidekiq/api'

  # Check queues
  Sidekiq::Queue.all.each do |queue|
    puts "Queue '#{queue.name}': #{queue.size} jobs"
    queue.each do |job|
      if job.klass == 'DomainWebContentExtractionWorker' && job.args.include?(27)
        puts "  - Found job for domain 27: #{job.created_at}"
      end
    end
  end

  # Check retry set
  retry_set = Sidekiq::RetrySet.new
  puts "Retry set: #{retry_set.size} jobs"

rescue => e
  puts "Could not check Sidekiq: #{e.message}"
end
