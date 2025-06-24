class CompanyEmployeeDiscoveryWorker
  include Sidekiq::Worker
  
  sidekiq_options queue: 'company_employee_discovery', retry: 3

  def perform(company_id)
    company = Company.find_by(id: company_id)
    return unless company
    
    Rails.logger.info "Starting employee discovery for company #{company.id} - #{company.company_name}"
    
    service = CompanyEmployeeDiscoveryService.new(company)
    result = service.perform
    
    if result.success?
      Rails.logger.info "Successfully discovered employees for company #{company.id}"
    else
      Rails.logger.error "Failed employee discovery for company #{company.id}: #{result.error}"
      raise result.error if result.data[:retry_after] # Re-raise for retry on rate limit
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Company not found: #{company_id}"
  rescue StandardError => e
    Rails.logger.error "Error in employee discovery worker: #{e.message}"
    raise # Re-raise for Sidekiq retry
  end
end