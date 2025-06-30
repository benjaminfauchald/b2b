class CompanyFinancialDataWorker
  include Sidekiq::Worker

  sidekiq_options queue: "company_financial_data", retry: 3

  def perform(company_id)
    company = Company.find_by(id: company_id)

    unless company
      Rails.logger.error "Company not found: #{company_id}"
      return
    end

    service = CompanyFinancialDataService.new(company)
    result = service.perform

    if result.success?
      Rails.logger.info "Successfully processed financial data for company #{company_id}"
    else
      # Check for retry_after in result.data hash or directly on result
      retry_after = nil
      if result.data&.is_a?(Hash) && result.data[:retry_after]
        retry_after = result.data[:retry_after]
      elsif result.respond_to?(:retry_after) && result.retry_after
        retry_after = result.retry_after
      end

      if retry_after
        Rails.logger.warn "Rate limited for company #{company_id}, retry after #{retry_after} seconds"
      else
        Rails.logger.error "Failed to process financial data for company #{company_id}: #{result.error}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error in CompanyFinancialDataWorker for company #{company_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise for Sidekiq retry
  end
end
