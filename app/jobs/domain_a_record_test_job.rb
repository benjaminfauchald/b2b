class DomainARecordTestJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: 0

  def perform(domain_id)
    domain = Domain.find(domain_id)

    Rails.logger.info "Starting A record test for domain: #{domain.domain}"

    service = DomainARecordTestingService.new(domain: domain)
    result = service.call

    Rails.logger.info "Completed A record test for domain: #{domain.domain}, result: #{result}"

    # Update domain with A record test result
    domain.update!(www: result)

    # Build context hash safely
    context = { domain_name: domain.domain, www_status: result ? "active" : "inactive" }
    if result.is_a?(Hash)
      context[:test_duration_ms] = (result[:duration] * 1000).to_i if result[:duration]
      context[:a_records] = result[:a_records] if result[:a_records]
      context[:error] = result[:error] if result[:error]
    end

    # Create audit log
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: "domain_a_record_testing",
      operation_type: "test_a_record",
      status: result ? :success : :failed,
      columns_affected: [ "www" ],
      metadata: {
        domain_name: domain.domain,
        result: result,
        job: self.class.name,
        job_id: job_id
      }
    )

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Domain not found: #{domain_id}"
    raise e
  rescue StandardError => e
    Rails.logger.error "Error in A record test job for domain #{domain_id}: #{e.message}"

    # Create error audit log
    if domain
      ServiceAuditLog.create!(
        auditable: domain,
        service_name: "domain_a_record_testing",
        operation_type: "test_a_record",
        status: :failed,
        error_message: e.message,
        columns_affected: [ "www" ],
        metadata: {
          domain_name: domain.domain,
          error: e.message,
          job: self.class.name,
          job_id: job_id
        }
      )
    end

    raise e
  end
end
