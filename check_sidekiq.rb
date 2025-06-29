require 'sidekiq/api'

puts "Sidekiq Queue Status:"
puts "==================="

# Check default queue for web content extraction workers
default_queue = Sidekiq::Queue.new("default")
puts "Default queue size: #{default_queue.size}"

web_content_jobs = default_queue.select { |job| job.klass == "DomainWebContentExtractionWorker" }
puts "Web content extraction jobs in queue: #{web_content_jobs.size}"

if web_content_jobs.any?
  puts "Web content jobs:"
  web_content_jobs.each do |job|
    puts "  - Job ID: #{job.jid}, Args: #{job.args}, Created: #{Time.at(job.created_at)}"
  end
end

puts ""
puts "Sidekiq workers:"
Sidekiq::Workers.new.each do |process_id, thread_id, work|
  puts "  - #{work['payload']['class']} (#{work['run_at']})"
end

puts ""
puts "Manual trigger web content extraction for domain 27:"
puts "DomainWebContentExtractionWorker.perform_async(27)"
