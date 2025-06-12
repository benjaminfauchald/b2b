class DomainARecordTestJob < ApplicationJob
  queue_as :DomainARecordTestingService
  
  sidekiq_options retry: 0

  def perform(domain_id)
    domain = Domain.find(domain_id)
    DomainARecordTestingService.test_a_record(domain)
  end
end 