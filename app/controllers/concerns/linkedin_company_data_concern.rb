# frozen_string_literal: true

# LinkedIn Company Data Concern
# Provides controller methods for LinkedIn company data extraction
# Include this in controllers that need LinkedIn company data functionality
module LinkedinCompanyDataConcern
  extend ActiveSupport::Concern

  included do
    # Add any before_actions or other controller-level configurations here
  end

  # Queue LinkedIn company data extraction
  def queue_linkedin_company_data
    @company = Company.find(params[:id])
    
    begin
      # Extract LinkedIn company data
      result = LinkedinCompanyDataService.new(
        company_identifier: linkedin_identifier_for_company(@company)
      ).call
      
      if result[:success]
        # Update company with LinkedIn data if needed
        update_company_with_linkedin_data(@company, result[:data])
        
        respond_to do |format|
          format.html { redirect_to @company, notice: 'LinkedIn company data extracted successfully.' }
          format.json { render json: { success: true, data: result[:data] } }
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace("linkedin_company_data_frame_#{@company.id}", 
                                   render_to_string(partial: 'shared/linkedin_company_data_result', 
                                                    locals: { company: @company, result: result }))
            ]
          end
        end
      else
        handle_linkedin_extraction_error(result[:error])
      end
      
    rescue StandardError => e
      Rails.logger.error "LinkedIn company data extraction failed: #{e.message}"
      handle_linkedin_extraction_error(e.message)
    end
  end

  # Get LinkedIn company data extraction status
  def linkedin_company_data_status
    @company = Company.find(params[:id])
    
    # Get latest audit log for this company
    audit_log = ServiceAuditLog.where(
      service_name: 'linkedin_company_data',
      auditable: @company
    ).order(created_at: :desc).first
    
    if audit_log
      status_data = {
        status: audit_log.status,
        updated_at: audit_log.updated_at,
        execution_time: audit_log.execution_time_ms
      }
      
      if audit_log.status == 'success'
        status_data[:company_data] = audit_log.metadata
      elsif audit_log.status == 'failed'
        status_data[:error] = audit_log.error_message
      end
      
      render json: status_data
    else
      render json: { status: 'unknown' }
    end
  end

  private

  def linkedin_identifier_for_company(company)
    # Try to determine LinkedIn identifier from company data
    # This is a placeholder - you may need to customize based on your Company model
    
    # Option 1: If company has a linkedin_url field
    if company.respond_to?(:linkedin_url) && company.linkedin_url.present?
      return company.linkedin_url
    end
    
    # Option 2: If company has a linkedin_id field
    if company.respond_to?(:linkedin_id) && company.linkedin_id.present?
      return company.linkedin_id
    end
    
    # Option 3: Search by company name
    if company.name.present?
      return company.name.downcase.gsub(/\s+/, '-')
    end
    
    # Fallback: use company name as-is
    company.name
  end

  def update_company_with_linkedin_data(company, linkedin_data)
    # Update company with LinkedIn data
    # Customize this based on your Company model fields
    
    update_fields = {}
    
    # Map LinkedIn data to company fields
    update_fields[:linkedin_id] = linkedin_data[:id] if company.respond_to?(:linkedin_id)
    update_fields[:linkedin_url] = "https://www.linkedin.com/company/#{linkedin_data[:universal_name]}" if company.respond_to?(:linkedin_url)
    update_fields[:description] = linkedin_data[:description] if company.respond_to?(:description) && linkedin_data[:description].present?
    update_fields[:website] = linkedin_data[:website] if company.respond_to?(:website) && linkedin_data[:website].present?
    update_fields[:industry] = linkedin_data[:industry] if company.respond_to?(:industry) && linkedin_data[:industry].present?
    update_fields[:staff_count] = linkedin_data[:staff_count] if company.respond_to?(:staff_count) && linkedin_data[:staff_count].present?
    
    # Add headquarters information if company has address fields
    if linkedin_data[:headquarters]
      hq = linkedin_data[:headquarters]
      update_fields[:city] = hq[:city] if company.respond_to?(:city) && hq[:city].present?
      update_fields[:country] = hq[:country] if company.respond_to?(:country) && hq[:country].present?
      update_fields[:postal_code] = hq[:postal_code] if company.respond_to?(:postal_code) && hq[:postal_code].present?
    end
    
    # Update company if there are fields to update
    if update_fields.any?
      company.update!(update_fields)
      Rails.logger.info "Updated company #{company.id} with LinkedIn data: #{update_fields.keys.join(', ')}"
    end
  end

  def handle_linkedin_extraction_error(error_message)
    respond_to do |format|
      format.html { redirect_to @company, alert: "LinkedIn extraction failed: #{error_message}" }
      format.json { render json: { success: false, error: error_message }, status: :unprocessable_entity }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("linkedin_company_data_frame_#{@company.id}", 
                               render_to_string(partial: 'shared/linkedin_company_data_error', 
                                                locals: { company: @company, error: error_message }))
        ]
      end
    end
  end
end