# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, type: :model do
  describe "web discovery scopes" do
    let!(:high_revenue_no_website) do
      create(:company,
        operating_revenue: 15_000_000,
        website: nil,
        web_pages: nil
      )
    end

    let!(:high_revenue_empty_website) do
      create(:company,
        operating_revenue: 20_000_000,
        website: "",
        web_pages: {}
      )
    end

    let!(:high_revenue_with_website) do
      create(:company,
        operating_revenue: 25_000_000,
        website: "https://example.com",
        web_pages: nil
      )
    end

    let!(:low_revenue_no_website) do
      create(:company,
        operating_revenue: 5_000_000,
        website: nil,
        web_pages: nil
      )
    end

    let!(:high_revenue_no_website_processed) do
      create(:company,
        operating_revenue: 30_000_000,
        website: nil,
        web_pages: [ { url: "https://found.com", title: "Found Site" } ]
      )
    end

    describe ".web_discovery_candidates" do
      it "includes companies with revenue > 10M NOK and no website" do
        candidates = Company.web_discovery_candidates

        expect(candidates).to include(high_revenue_no_website)
        expect(candidates).to include(high_revenue_empty_website)
        expect(candidates).to include(high_revenue_no_website_processed)
      end

      it "excludes companies with websites" do
        candidates = Company.web_discovery_candidates

        expect(candidates).not_to include(high_revenue_with_website)
      end

      it "excludes companies with revenue <= 10M NOK" do
        candidates = Company.web_discovery_candidates

        expect(candidates).not_to include(low_revenue_no_website)
      end
    end

    describe ".needing_web_discovery" do
      it "includes only unprocessed companies with revenue > 10M NOK and no website" do
        needing = Company.needing_web_discovery

        expect(needing).to include(high_revenue_no_website)
        expect(needing).to include(high_revenue_empty_website)
      end

      it "excludes companies that have been processed (have web_pages)" do
        needing = Company.needing_web_discovery

        expect(needing).not_to include(high_revenue_no_website_processed)
      end

      it "excludes companies with websites" do
        needing = Company.needing_web_discovery

        expect(needing).not_to include(high_revenue_with_website)
      end

      it "excludes companies with revenue <= 10M NOK" do
        needing = Company.needing_web_discovery

        expect(needing).not_to include(low_revenue_no_website)
      end
    end

    describe ".web_discovery_potential" do
      it "includes all companies with revenue > 10M NOK and no website" do
        potential = Company.web_discovery_potential

        expect(potential).to include(high_revenue_no_website)
        expect(potential).to include(high_revenue_empty_website)
        expect(potential).to include(high_revenue_no_website_processed)
      end

      it "excludes companies with websites" do
        potential = Company.web_discovery_potential

        expect(potential).not_to include(high_revenue_with_website)
      end

      it "excludes companies with revenue <= 10M NOK" do
        potential = Company.web_discovery_potential

        expect(potential).not_to include(low_revenue_no_website)
      end
    end
  end

  describe "ServiceAuditable integration" do
    let!(:service_config) do
      ServiceConfiguration.find_or_create_by!(service_name: "company_web_discovery") do |config|
        config.active = true
        config.refresh_interval_hours = 720
      end
    end

    let!(:company_needing_discovery) do
      create(:company,
        operating_revenue: 15_000_000,
        website: nil,
        web_pages: nil
      )
    end

    describe ".needing_service" do
      it "uses needing_web_discovery scope for company_web_discovery service" do
        companies = Company.needing_service("company_web_discovery")

        expect(companies).to include(company_needing_discovery)
      end

      it "returns empty when service is inactive" do
        service_config.update!(active: false)

        companies = Company.needing_service("company_web_discovery")

        expect(companies).to be_empty
      end
    end
  end
end
