class DomainMxTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'domain_mx_testing', retry: 3

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain

    service = DomainMxTestingService.new(domain: domain)
    result = service.call

    if result[:status] == :success
      domain.update(
        mx: result[:mx_records].any?,
        mx_records: result[:mx_records],
        last_mx_check: Time.current
      )
    else
      domain.update(
        mx: false,
        mx_error: result[:error],
        last_mx_check: Time.current
      )
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Domain ##{domain_id} not found for MX testing"
  rescue StandardError => e
    Rails.logger.error "Error testing MX for domain ##{domain_id}: #{e.message}"
    raise
  end
end 