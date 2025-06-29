require "ostruct"

class CompanyFinancialDataService < ApplicationService
  def initialize(company)
    @company = company
    super(service_name: "company_financial_data", action: "process")
  end

  def perform
    return error_result("Service is disabled") unless service_active?

    audit_service_operation(@company) do |audit_log|
      unless needs_update?
        audit_log.update!(
          status: :success,
          metadata: audit_log.metadata.merge(reason: "up_to_date", skipped: true),
          completed_at: Time.current,
          execution_time_ms: ((Time.current - audit_log.started_at) * 1000).round
        )
        # Early return to avoid API call
        next success_result("Financial data is up to date")
      end

      # Fetch financial data from external API
      response = fetch_financial_data
      Rails.logger.debug "API Response: #{response.inspect}" if Rails.env.test?

      if response[:success]
        if response[:no_data_available]
          # No financial data available for this company
          metadata = {
            api_response_code: response[:unsupported_format] ? 500 : 404,
            no_data_available: true
          }
          metadata[:unsupported_format] = true if response[:unsupported_format]
          audit_log.add_metadata(metadata)
          success_result("No financial data available for this company")
        else
          # Validate the financial data structure
          unless valid_financial_data?(response[:data])
            raise StandardError.new("Invalid financial data structure")
          end

          update_company_financials(response[:data])

          # Add metadata for successful API response
          audit_log.add_metadata(
            api_response_code: 200,
            financial_data: response[:data]
          )

          success_result("Financial data updated", financial_data: response[:data])
        end
      elsif response[:rate_limited]
        # Create a custom exception that includes the retry_after info
        error = StandardError.new("API rate limit exceeded")
        error.define_singleton_method(:retry_after) { response[:retry_after] }
        raise error
      else
        raise StandardError.new(response[:error] || "Failed to fetch financial data")
      end
    end
  rescue StandardError => e
    # For rate limit errors, include retry_after in the result data
    if e.message.include?("rate limit") && e.respond_to?(:retry_after)
      error_result(e.message, retry_after: e.retry_after)
    else
      error_result("Service error: #{e.message}")
    end
  end

  private

  def service_active?
    config = ServiceConfiguration.find_by(service_name: "company_financial_data")
    config&.active?
  end

  def needs_update?
    # Use the ServiceAuditable concern's needs_service? method which checks audit logs
    @company.needs_service?("company_financial_data")
  end

  def fetch_financial_data
    require "net/http"
    require "json"

    # Use the same endpoint as defined in the test
    api_endpoint = ENV["BRREG_API_ENDPOINT"] || "https://data.brreg.no"
    registration_number = @company.registration_number

    begin
      uri = URI("#{api_endpoint}/regnskapsregisteret/regnskap/#{registration_number}")
      Rails.logger.debug "Fetching financial data from: #{uri}" if Rails.env.test?
      response = Net::HTTP.get_response(uri)

      case response.code.to_i
      when 200
        data = JSON.parse(response.body, symbolize_names: true)

        # Handle Array response - extract most recent financial data
        if data.is_a?(Array)
          if data.empty?
            return { success: true, data: nil, no_data_available: true }
          end

          # Get the most recent financial record
          latest_record = data.max_by { |record| record[:regnskapsperiode]&.dig(:fraDato) || "0000-01-01" }

          # Transform API response to expected format
          transformed_data = {
            revenue: latest_record.dig(:resultatregnskapResultat, :driftsresultat, :driftsinntekter, :sumDriftsinntekter) ||
                    latest_record.dig(:resultatregnskapResult, :driftsresultat, :driftsinntekter, :sum),
            profit: latest_record.dig(:resultatregnskapResultat, :aarsresultat) ||
                   latest_record.dig(:resultatregnskapResult, :aarsresultat),
            equity: latest_record.dig(:egenkapitalGjeld, :egenkapital, :sumEgenkapital) ||
                   latest_record.dig(:balanseregnskapResult, :egenkapitalGjeld, :egenkapital, :sum),
            total_assets: latest_record.dig(:eiendeler, :sumEiendeler) ||
                         latest_record.dig(:balanseregnskapResult, :eiendeler, :sum),
            current_assets: latest_record.dig(:eiendeler, :omloepsmidler, :sumOmloepsmidler) ||
                           latest_record.dig(:balanseregnskapResult, :eiendeler, :omloepsmidler, :sum),
            fixed_assets: latest_record.dig(:eiendeler, :anleggsmidler, :sumAnleggsmidler) ||
                         latest_record.dig(:balanseregnskapResult, :eiendeler, :anleggsmidler, :sum),
            current_liabilities: latest_record.dig(:egenkapitalGjeld, :gjeldOversikt, :kortsiktigGjeld, :sumKortsiktigGjeld) ||
                                latest_record.dig(:balanseregnskapResult, :egenkapitalGjeld, :gjeld, :kortsiktigGjeld, :sum),
            long_term_liabilities: latest_record.dig(:egenkapitalGjeld, :gjeldOversikt, :langsiktigGjeld, :sumLangsiktigGjeld) ||
                                  latest_record.dig(:balanseregnskapResult, :egenkapitalGjeld, :gjeld, :langsiktigGjeld, :sum),
            year: latest_record.dig(:regnskapsperiode, :fraDato)&.slice(0, 4)&.to_i
          }

          { success: true, data: transformed_data }
        else
          { success: true, data: data }
        end
      when 404
        # 404 means no financial data available for this company
        { success: true, data: nil, no_data_available: true }
      when 429
        retry_after = response["Retry-After"]&.to_i || 3600
        { success: false, rate_limited: true, retry_after: retry_after }
      when 500
        # Handle specific 500 errors
        error_body = JSON.parse(response.body) rescue {}
        error_message = error_body["message"] || response.message

        if error_message&.include?("oppstillingsplan som ikke er stottet")
          # Unsupported account layout plan - treat as no data available
          { success: true, data: nil, no_data_available: true, unsupported_format: true }
        else
          { success: false, error: "API error: #{response.code} - #{error_message}" }
        end
      else
        { success: false, error: "API error: #{response.code} - #{response.message}" }
      end
    rescue StandardError => e
      { success: false, error: "Request failed: #{e.message}" }
    end
  end

  def valid_financial_data?(data)
    required_fields = [ :revenue, :profit, :equity, :total_assets, :current_assets,
                      :fixed_assets, :current_liabilities, :long_term_liabilities, :year ]

    data.is_a?(Hash) && required_fields.all? { |field| data.key?(field) }
  end

  def update_company_financials(data)
    @company.update!(
      revenue: data[:revenue],
      profit: data[:profit],
      equity: data[:equity],
      total_assets: data[:total_assets],
      current_assets: data[:current_assets],
      fixed_assets: data[:fixed_assets],
      current_liabilities: data[:current_liabilities],
      long_term_liabilities: data[:long_term_liabilities],
      year: data[:year],
      financial_data_updated_at: Time.current
    )
  end

  def success_result(message, data = {})
    OpenStruct.new(
      success?: true,
      message: message,
      data: data,
      error: nil
    )
  end

  def error_result(message, data = {})
    OpenStruct.new(
      success?: false,
      message: nil,
      error: message,
      data: data
    )
  end
end
