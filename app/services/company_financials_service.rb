# frozen_string_literal: true

class CompanyFinancialsService < ApplicationService
  SERVICE_NAME = 'company_financials'.freeze
  
  def initialize(company_id: nil, batch_size: 100, force: false)
    @company_id = company_id
    @batch_size = batch_size
    @force = force
    super(service_name: SERVICE_NAME, action: 'update_financials')
  end
  
  def call
    if @company_id
      update_single_company
    else
      update_companies_in_batches
    end
  end
  
  private
  
  def update_single_company
    company = Company.find(@company_id)
    audit_log = start_audit_log(company.id)
    
    begin
      result = CompanyFinancialsUpdater.new(company).call
      
      if result[:success]
        changed_fields = Array(result[:changed_fields]).map(&:to_s)
        audit_log.mark_success!(
          changed_fields: changed_fields,
          context: {
            registration_number: company.registration_number.to_s,
            company_name: company.company_name.to_s,
            updated_fields: changed_fields.join(',')
          }
        )
      else
        raise StandardError, "Failed to update financial data"
      end
    rescue => e
      # Create a new string to avoid frozen string issues
      error_message = "#{e.class.name}: #{e.message}".dup
      
      audit_log.mark_failed!(
        error_message,
        registration_number: company.registration_number.to_s,
        company_name: company.company_name.to_s,
        error_class: e.class.name.to_s
      )
      
      # Re-raise the original error
      raise e
    end
  end
  
  def update_companies_in_batches
    scope = @force ? Company.all : Company.where("http_error IS NOT NULL OR http_error IS NULL OR updated_at < ?", 1.month.ago)
    total = scope.count
    processed = 0
    
    scope.find_in_batches(batch_size: @batch_size) do |batch|
      batch.each do |company|
        update_company_with_retry(company)
        processed += 1
        print "\rProcessing: #{processed}/#{total} companies"
      end
    end
    
    puts "\nCompleted processing #{processed} companies"
  end
  
  def update_company_with_retry(company)
    retry_count = 0
    max_retries = 3
    
    begin
      audit_log = start_audit_log(company.id)
      result = CompanyFinancialsUpdater.new(company).call
      
      audit_log.mark_success!(
        changed_fields: result[:changed_fields],
        context: {
          registration_number: company.registration_number,
          company_name: company.company_name,
          updated_fields: result[:changed_fields].join(',')
        }
      )
      
    rescue => e
      retry_count += 1
      if retry_count <= max_retries
        sleep(2 ** retry_count) # Exponential backoff
        retry
      end
      
      audit_log&.mark_failed!("#{e.class.name}: #{e.message}", {
        registration_number: company.registration_number,
        company_name: company.company_name,
        error_class: e.class.name,
        retry_count: retry_count
      })
      
      # Log the error but continue with the next company
      Rails.logger.error("Failed to update company ##{company.id} after #{max_retries} retries: #{e.message}")
    end
  end
  
  def start_audit_log(company_id)
    company = Company.find(company_id)
    ServiceAuditLog.create!(
      service_name: SERVICE_NAME,
      action: 'update_financials',
      status: :pending,
      auditable: company,
      started_at: Time.current
    )
  rescue => e
    Rails.logger.error("Failed to create audit log for company #{company_id}: #{e.message}")
    raise
  end
end
