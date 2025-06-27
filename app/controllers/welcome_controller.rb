class WelcomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]

  def index
    @domain_count = Domain.count
    @company_count = Company.count
    @total_processed = ServiceAuditLog.where(status: "success").count
    @services_active = ServiceConfiguration.where(active: true).count
  end
end
