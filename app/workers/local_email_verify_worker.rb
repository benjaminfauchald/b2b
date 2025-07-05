# frozen_string_literal: true

class LocalEmailVerifyWorker
  include Sidekiq::Worker

  sidekiq_options queue: :email_verification, retry: 3

  def perform(person_id, retry_count = 0)
    person = Person.find_by(id: person_id)
    return unless person && person.email.present?

    # Use hybrid service if available and active, fallback to local
    service = if ServiceConfiguration.find_by(service_name: "hybrid_email_verify")&.active?
                People::HybridEmailVerifyService.new(
                  person: person,
                  metadata: { retry_count: retry_count }
                )
    else
                People::LocalEmailVerifyService.new(
                  person: person,
                  metadata: { retry_count: retry_count }
                )
    end

    result = service.perform

    Rails.logger.info "Email verification completed for person #{person_id} using #{service.class.name}: #{result.message}"
  rescue StandardError => e
    Rails.logger.error "Email verification failed for person #{person_id}: #{e.message}"
    raise e
  end
end
