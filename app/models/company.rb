class Company < ApplicationRecord
  # Associations
  has_many :service_audit_logs, as: :auditable, dependent: :nullify
  
  # Validations
  validates :registration_number, presence: true, uniqueness: true
  
  # Scopes for financial data
  scope :with_financial_data, -> { where.not(ordinary_result: nil, annual_result: nil) }
  scope :without_financial_data, -> { where(ordinary_result: nil, annual_result: nil) }
  scope :needs_financial_update, -> { 
    # Find companies that either:
    # 1. Have no financial data at all, OR
    # 2. Their last successful financial update was more than 6 months ago
    six_months_ago = 6.months.ago
    
    # Using Arel for the join to be more Rails-idiomatic
    companies_table = arel_table
    audit_logs = ServiceAuditLog.arel_table
    
    join_condition = audit_logs[:auditable_id].eq(companies_table[:id])
      .and(audit_logs[:auditable_type].eq('Company'))
      .and(audit_logs[:service_name].eq('company_financials'))
      .and(audit_logs[:status].eq(ServiceAuditLog.statuses[:success]))
    
    # Left outer join with conditions
    query = companies_table
      .join(audit_logs, Arel::Nodes::OuterJoin)
      .on(join_condition)
      .where(
        companies_table[:ordinary_result].eq(nil)
          .or(companies_table[:annual_result].eq(nil))
          .or(audit_logs[:id].eq(nil))
          .or(audit_logs[:completed_at].lt(six_months_ago))
      )
      .project(companies_table[Arel.star])
      .distinct
    
    # Convert back to ActiveRecord relation
    find_by_sql(query.to_sql)
  }
  
  # Instance Methods
  
  # Update financial data asynchronously
  def update_financials_async
    CompanyFinancialsService.new(company_id: id).call
  end
  
  # Update financial data synchronously
  def update_financials_sync
    CompanyFinancialsService.new(company_id: id).call
  end
  
  # Check if financial data is missing
  def financial_data_missing?
    ordinary_result.nil? || annual_result.nil? || http_error.present? || 
      last_financial_audit.nil? || last_financial_audit.completed_at < 1.month.ago
  end
  
  # Check if financial data is stale
  def financial_data_stale?
    last_successful_audit = service_audit_logs
      .where(service_name: 'company_financials', status: :success)
      .order(completed_at: :desc)
      .first
      
    last_successful_audit.nil? || last_successful_audit.completed_at < 6.months.ago
  end
  
  # Check if company needs a financial update
  def needs_financial_update?
    ordinary_result.nil? || 
    annual_result.nil? || 
    financial_data_stale?
  end
  
  # Get financial data summary
  def financial_data
    {
      ordinary_result: ordinary_result,
      annual_result: annual_result,
      operating_revenue: operating_revenue,
      operating_costs: operating_costs,
      last_updated: last_financial_audit&.completed_at || updated_at,
      status: financial_data_status
    }
  end
  
  # Returns the status of the most recent financial data update via SCT
  def financial_data_status
    audit = ServiceAuditLog.where(auditable: self, service_name: 'company_financials').order(completed_at: :desc).first
    return 'pending' if audit.nil?
    audit.status_success? ? 'success' : 'failed'
  end
  
  # Returns the completed_at timestamp of the most recent financial data update via SCT
  def last_financial_update_at
    ServiceAuditLog.where(auditable: self, service_name: 'company_financials', status: ServiceAuditLog.statuses[:success])
      .order(completed_at: :desc)
      .limit(1)
      .pick(:completed_at)
  end
  
  # For backward compatibility
  def last_financial_audit
    @last_financial_audit ||= ServiceAuditLog
      .where(auditable: self, service_name: 'company_financials')
      .order(completed_at: :desc)
      .first
  end
end