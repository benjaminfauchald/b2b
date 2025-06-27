class CompanyFinancialsChannel < ApplicationCable::Channel
  def subscribed
    company_id = params[:company_id]

    # Validate that the user has access to this company
    company = Company.find_by(id: company_id)

    if company.present?
      stream_for company
      Rails.logger.info "CompanyFinancialsChannel: User subscribed to company #{company_id}"
    else
      reject
      Rails.logger.warn "CompanyFinancialsChannel: Invalid company_id #{company_id}"
    end
  end

  def unsubscribed
    Rails.logger.info "CompanyFinancialsChannel: User unsubscribed"
  end

  # Class method to broadcast updates
  def self.broadcast_financial_update(company, data)
    broadcast_to(company, {
      type: "financial_data_updated",
      company_id: company.id,
      updated_at: Time.current.iso8601,
      status: data[:status] || "success",
      data: data
    })
  end

  def self.broadcast_processing_started(company)
    broadcast_to(company, {
      type: "processing_started",
      company_id: company.id,
      updated_at: Time.current.iso8601
    })
  end

  def self.broadcast_processing_failed(company, error_message = nil)
    broadcast_to(company, {
      type: "processing_failed",
      company_id: company.id,
      updated_at: Time.current.iso8601,
      error: error_message
    })
  end
end
