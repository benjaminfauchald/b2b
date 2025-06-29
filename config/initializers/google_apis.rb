# Ensure Google API gems are loaded for Sidekiq workers
begin
  require "google/apis/customsearch_v1"
  require "openai"
rescue LoadError => e
  Rails.logger.warn "Could not load Google API dependencies: #{e.message}"
end
