# frozen_string_literal: true

class LocalEmailVerifyWorker
  include Sidekiq::Worker

  sidekiq_options queue: :email_verification, retry: 3

  def perform(person_id, retry_count = 0)
    person = Person.find_by(id: person_id)
    return unless person && person.email.present?

    service = People::LocalEmailVerifyService.new(
      person: person,
      metadata: { retry_count: retry_count }
    )

    result = service.perform

    Rails.logger.info "Email verification completed for person #{person_id}: #{result.message}"
  rescue StandardError => e
    Rails.logger.error "Email verification failed for person #{person_id}: #{e.message}"
    raise e
  end
end
