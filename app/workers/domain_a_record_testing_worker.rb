class DomainARecordTestingWorker
  include Sidekiq::Worker

  sidekiq_options queue: "DomainARecordTestingService", retry: 0

  def perform(domain_id)
    domain = Domain.find(domain_id)
    service = DomainARecordTestingService.new(domain: domain)
    result = service.call

    # Update domain with A record test result
    domain.update!(www: result)

    # Create audit log
    context = {
      domain_name: domain.domain,
      www_status: result ? "active" : "inactive"
    }
    if result.is_a?(Hash)
      context[:test_duration_ms] = (result[:duration] * 1000).to_i if result[:duration]
      context[:a_records] = result[:a_records] if result[:a_records]
      context[:error] = result[:error] if result[:error]
    end
    ServiceAuditLog.create!(
      auditable: domain,
      service_name: "domain_a_record_testing",
      operation_type: "test_a_record",
      status: result ? :success : :failed,
      context: context
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Domain not found: #{domain_id}"
    raise e
  rescue StandardError => e
    Rails.logger.error "Error processing domain #{domain_id}: #{e.message}"

    # Create audit log for the error
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
          worker: self.class.name
        }
      )
    end

    raise e
  end
end
