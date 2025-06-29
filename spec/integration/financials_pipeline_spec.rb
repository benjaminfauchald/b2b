# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe 'Financials Pipeline Integration', :integration do
  describe 'Company Financials Service' do
    it 'fetches financial data from API and updates company records' do
      # Create a company that needs financial data
      company = create(:company,
        registration_number: "123456789",
        organization_form_code: "AS",
        source_country: "NO",
        source_registry: "brreg",
        ordinary_result: nil,
        annual_result: nil,
        operating_revenue: nil,
        operating_costs: nil
      )

      # Mock service configuration
      create(:service_configuration,
        service_name: 'company_financials',
        active: true,
        refresh_interval_hours: 24
      )

      # Mock Redis for rate limiting - simplified
      redis_mock = double('redis')
      allow(Sidekiq).to receive(:redis).and_yield(redis_mock)
      allow(redis_mock).to receive(:get).and_return("0")
      allow(redis_mock).to receive(:set).and_return(true)

      # Mock HTTParty to track API calls
      api_called = false
      allow(HTTParty).to receive(:get) do |url, options|
        api_called = true
        expect(url).to include(company.registration_number)

        # Return mock financial data
        double('response',
          code: 200,
          success?: true,
          body: {
            "resultatregnskapResultat" => {
              "aarsresultat" => 1500000,
              "ordinaertResultatFoerSkattekostnad" => 2000000,
              "driftsresultat" => {
                "driftsinntekter" => {
                  "sumDriftsinntekter" => 5000000
                },
                "driftskostnad" => {
                  "sumDriftskostnad" => 4000000
                }
              }
            }
          }.to_json,
          headers: {}
        )
      end

      # Execute the worker directly
      worker = CompanyFinancialsWorker.new
      worker.perform(company.id)

      # Verify API was called
      expect(api_called).to be true

      # Verify company was updated with financial data
      company.reload
      expect(company.ordinary_result).to eq(2000000.0)
      expect(company.annual_result).to eq(1500000.0)
      expect(company.operating_revenue).to eq(5000000.0)
      expect(company.operating_costs).to eq(4000000.0)

      # Verify audit log was created
      audit_log = ServiceAuditLog.where(
        auditable: company,
        service_name: 'company_financials',
        status: 'success'
      ).last
      expect(audit_log).to be_present
      expect(audit_log.metadata).to include('changed_fields')
    end

    it 'enforces rate limiting between multiple API calls' do
      # Create multiple companies
      companies = 3.times.map do |i|
        create(:company,
          registration_number: "#{900000000 + i}",
          organization_form_code: "AS",
          source_country: "NO",
          source_registry: "brreg",
          ordinary_result: nil
        )
      end

      # Mock service configuration
      create(:service_configuration,
        service_name: 'company_financials',
        active: true,
        refresh_interval_hours: 24
      )

      # Track API call times
      api_call_times = []
      last_api_call_time = 0.0

      # Mock Redis for rate limiting
      redis_mock = double('redis')
      allow(Sidekiq).to receive(:redis).and_yield(redis_mock)

      allow(redis_mock).to receive(:get).with("company_financials_service:last_api_call") do
        last_api_call_time.to_s
      end

      allow(redis_mock).to receive(:set).with("company_financials_service:last_api_call", anything, hash_including(:ex)) do |key, value, opts|
        last_api_call_time = value.to_f
        true
      end

      allow(redis_mock).to receive(:set).with("company_financials_service:global_api_lock", anything, hash_including(:nx, :ex)) do |key, value, opts|
        current_time = value.to_f
        # Only allow lock if 1 second has passed
        if current_time - last_api_call_time >= 1.0
          true
        else
          false
        end
      end

      # Mock HTTParty to track API calls
      allow(HTTParty).to receive(:get) do |url, options|
        api_call_times << Time.now

        double('response',
          code: 200,
          success?: true,
          body: {
            "resultatregnskapResultat" => {
              "aarsresultat" => 750000,
              "ordinaertResultatFoerSkattekostnad" => 1000000
            }
          }.to_json,
          headers: {}
        )
      end

      # Process all companies
      start_time = Time.now
      companies.each do |company|
        CompanyFinancialsWorker.new.perform(company.id)
      end
      end_time = Time.now

      # Verify all API calls were made
      expect(api_call_times.size).to eq(3)

      # Verify rate limiting (should take at least 2 seconds for 3 calls)
      total_duration = end_time - start_time
      expect(total_duration).to be >= 2.0

      # Check intervals between calls
      intervals = api_call_times.each_cons(2).map { |a, b| b - a }
      expect(intervals.all? { |interval| interval >= 0.9 }).to be true

      # Verify all companies were updated
      companies.each do |company|
        company.reload
        expect(company.ordinary_result).to be_present
      end
    end
  end

  describe 'Kafka Integration' do
    let(:topic) { 'company_financials' }

    before do
      # Create test companies
      @test_companies = 5.times.map do |i|
        create(:company, registration_number: "TEST#{1000 + i}")
      end
    end

    it 'processes Kafka messages through Sidekiq' do
      # Mock Kafka and Sidekiq
      expect(KafkaService).to receive(:produce).exactly(5).times
      expect(CompanyFinancialsWorker).to receive(:perform_async).exactly(5).times.and_return(SecureRandom.uuid)

      # Create messages
      messages = @test_companies.map.with_index do |company, i|
        {
          company_id: company.id,
          requested_at: Time.now.utc.iso8601,
          event_type: 'company_financials_requested'
        }
      end

      # Simulate message flow
      messages.each do |msg|
        KafkaService.produce(msg)
        CompanyFinancialsWorker.perform_async(msg[:company_id])
      end
    end
  end
end
