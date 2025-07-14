class LinkedinCompanySlugWorker
  include Sidekiq::Worker
  
  sidekiq_options retry: 2, queue: :linkedin_slug_population, backtrace: true

  def perform
    LinkedinCompanySlugService.new.perform
  end
end