require 'rails_helper'
require 'benchmark'

RSpec.describe "Web Discovery Performance", type: :model do
  fixtures :companies, :service_configurations

  describe "query performance" do
    before do
      # Ensure we have enough test data
      @high_revenue_companies = Company.where("operating_revenue > ?", 10_000_000)
      skip "Not enough test data" if @high_revenue_companies.count < 10
    end

    it "efficiently queries companies needing web discovery" do
      time = Benchmark.realtime do
        companies = Company.needing_web_discovery.limit(100).to_a
      end

      expect(time).to be < 0.1 # Query should complete in under 100ms
    end

    it "efficiently calculates web discovery statistics" do
      time = Benchmark.realtime do
        total = Company.where("operating_revenue > ?", 10_000_000).count
        with_websites = Company.where("operating_revenue > ?", 10_000_000)
                               .where.not(website: [ nil, "" ]).count
        percentage = (with_websites.to_f / total.to_f * 100).round(2)
      end

      expect(time).to be < 0.2 # Stats calculation should complete in under 200ms
    end

    it "handles country filtering efficiently" do
      countries = Company.distinct.pluck(:source_country).compact

      countries.each do |country|
        time = Benchmark.realtime do
          Company.by_country(country)
                 .where("operating_revenue > ?", 10_000_000)
                 .count
        end

        expect(time).to be < 0.05 # Each country query should be under 50ms
      end
    end
  end

  describe "service performance" do
    it "processes web discovery in reasonable time" do
      company = companies(:norwegian_company_no_website)
      skip "No suitable test company" unless company

      # Mock external API calls
      allow_any_instance_of(CompanyWebDiscoveryService).to receive(:google_search).and_return([
        { url: "https://example.no", title: "Example Company", snippet: "Company website" }
      ])

      allow_any_instance_of(CompanyWebDiscoveryService).to receive(:valid_company_website?).and_return(true)
      allow_any_instance_of(CompanyWebDiscoveryService).to receive(:validate_and_score_website).and_return({
        url: "https://example.no",
        title: "Example Company",
        confidence: 80,
        discovered_at: Time.current.iso8601
      })

      time = Benchmark.realtime do
        service = CompanyWebDiscoveryService.new(company_id: company.id)
        service.perform
      end

      expect(time).to be < 1.0 # Service should complete in under 1 second (with mocked APIs)
    end
  end
end
