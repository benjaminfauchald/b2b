# frozen_string_literal: true

require "rails_helper"

RSpec.describe "People Service Stats Consistency", type: :system do
  describe "Profile Extraction Card" do
    let!(:company1) { create(:company) }
    let!(:company2) { create(:company) }
    let!(:person1) { create(:person, company: company1, profile_url: "https://linkedin.com/in/person1") }
    let!(:person2) { create(:person, company: company1, profile_url: "https://linkedin.com/in/person2", profile_extracted_at: 1.day.ago) }
    let!(:person3) { create(:person, company: company2, profile_url: "https://linkedin.com/in/person3") }

    before do
      create(:service_configuration, service_name: "person_profile_extraction", active: true)
    end

    it "shows consistent totals in queue button and turbo frame updates" do
      # Check the scope used for determining who needs profile extraction
      # person1 and person3 have no service audit logs, person2 has profile_extracted_at set
      expect(Person.needs_profile_extraction.count).to eq(3) # All three need extraction based on the scope logic

      # The service_stats partial should show the same count
      people_needing = Person.needing_service("person_profile_extraction").count
      expect(people_needing).to eq(3)
    end
  end

  describe "Email Extraction Card" do
    let!(:person1) { create(:person, email_extracted_at: nil) }
    let!(:person2) { create(:person, email_extracted_at: 1.day.ago) }
    let!(:person3) { create(:person, email_extracted_at: 8.days.ago) }

    before do
      create(:service_configuration, service_name: "person_email_extraction", active: true)
    end

    it "shows consistent totals for email extraction needs" do
      # Check the scope - person1 (nil) and person3 (older than 7 days)
      expect(Person.needs_email_extraction.count).to eq(2) # person1 and person3

      # The service should show the same
      people_needing = Person.needing_service("person_email_extraction").count
      expect(people_needing).to eq(2)
    end
  end

  describe "Social Media Extraction Card" do
    let!(:person1) { create(:person, social_media_extracted_at: nil) }
    let!(:person2) { create(:person, social_media_extracted_at: 31.days.ago) }
    let!(:person3) { create(:person, social_media_extracted_at: 29.days.ago) }
    let!(:person4) { create(:person, social_media_extracted_at: 1.day.ago) }

    before do
      create(:service_configuration, service_name: "person_social_media_extraction", active: true)
    end

    it "shows consistent totals for social media extraction needs" do
      # Check the scope - should include those without social media extraction or older than 30 days
      expect(Person.needs_social_media_extraction.count).to eq(2) # person1 (nil) and person2 (31 days ago)

      # The service should show the same
      people_needing = Person.needing_service("person_social_media_extraction").count
      expect(people_needing).to eq(2)
    end
  end
end

RSpec.describe "Domain Service Stats Consistency", type: :system do
  describe "DNS Testing Card" do
    let!(:domain1) { create(:domain, dns: nil) }
    let!(:domain2) { create(:domain, dns: true) }
    let!(:domain3) { create(:domain, dns: nil) }

    before do
      create(:service_configuration, service_name: "domain_testing", active: true)
    end

    it "shows consistent totals for DNS testing needs" do
      # Domains needing DNS testing (those with dns: nil)
      expect(Domain.untested.count).to eq(2) # domain1 and domain3

      # Service should show the same
      domains_needing = Domain.needing_service("domain_testing").count
      expect(domains_needing).to eq(2)
    end
  end

  describe "MX Testing Card" do
    let!(:domain1) { create(:domain, dns: true, mx: nil) }
    let!(:domain2) { create(:domain, dns: true, mx: true) }
    let!(:domain3) { create(:domain, dns: true, mx: nil) }

    before do
      create(:service_configuration, service_name: "domain_mx_testing", active: true)
    end

    it "shows consistent totals for MX testing needs" do
      # Domains needing MX testing (those with dns: true and mx: nil)
      expect(Domain.dns_active.mx_untested.count).to eq(2) # domain1 and domain3

      # Service should show the same
      domains_needing = Domain.needing_service("domain_mx_testing").count
      expect(domains_needing).to eq(2)
    end
  end
end
