class LinkedinCompanyAssociationWorker
  include Sidekiq::Worker
  
  sidekiq_options retry: 3, queue: :linkedin_association, backtrace: true

  def perform(person_id = nil)
    if person_id
      # Process specific person
      person = Person.find(person_id)
      LinkedinCompanyAssociationService.new.call(person: person)
    else
      # Process all unassociated people
      LinkedinCompanyAssociationService.new.perform
    end
  end
end