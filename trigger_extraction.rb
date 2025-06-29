puts "Manually triggering web content extraction for domain 27:"
job_id = DomainWebContentExtractionWorker.perform_async(27)
puts "Job queued with ID: #{job_id}"

puts ""
puts "Checking queue after trigger:"
require 'sidekiq/api'
default_queue = Sidekiq::Queue.new("default")
puts "Default queue size: #{default_queue.size}"

web_content_jobs = default_queue.select { |job| job.klass == "DomainWebContentExtractionWorker" }
puts "Web content extraction jobs in queue: #{web_content_jobs.size}"
