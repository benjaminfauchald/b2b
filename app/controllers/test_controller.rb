class TestController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token

  def web_discovery_test
    # Only test companies with operating revenue over 10 million NOK - suitable targets for web discovery
    # Use the existing web_discovery_candidates scope which includes revenue filtering and orders by revenue
    @companies = Company.web_discovery_candidates_ordered.limit(5)
    @service_configs = ServiceConfiguration.all
  end

  def run_web_discovery
    company_id = params[:company_id]
    company = Company.find(company_id)

    # Run the web discovery service
    service = CompanyWebDiscoveryService.new(company_id: company_id)
    result = service.perform

    render json: {
      success: result.success?,
      message: result.success? ? result.message : result.error,
      data: result.data,
      company: {
        id: company.id,
        name: company.company_name,
        website: company.website,
        web_pages: company.web_pages
      }
    }
  end

  def linkedin_discovery_test
    # Only test companies with operating revenue over 10 million NOK - suitable targets for LinkedIn discovery
    # Use the LinkedIn discovery candidates scope which includes revenue filtering and orders by revenue
    @companies = Company.linkedin_discovery_candidates.limit(5)
    @service_configs = ServiceConfiguration.all
  end

  def run_linkedin_discovery
    company_id = params[:company_id]
    company = Company.find(company_id)

    # Run the LinkedIn discovery service
    service = CompanyLinkedinDiscoveryService.new(company_id: company_id)
    result = service.perform

    render json: {
      success: result.success?,
      message: result.success? ? result.message : result.error,
      data: result.data,
      company: {
        id: company.id,
        name: company.company_name,
        linkedin_url: company.linkedin_url,
        linkedin_data: company.linkedin_data
      }
    }
  end
end
