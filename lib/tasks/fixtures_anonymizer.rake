namespace :fixtures do
  desc "Generate anonymized fixtures from production data"
  task anonymize: :environment do
    require "faker"

    puts "Generating anonymized fixtures..."

    fixtures_dir = Rails.root.join("spec", "fixtures", "anonymized")
    FileUtils.mkdir_p(fixtures_dir)

    # Sample companies with anonymized data
    companies_to_anonymize = Company.limit(50).map do |company|
      {
        registration_number: "TEST#{company.id}",
        company_name: "#{Faker::Company.name} #{company.organization_form_code}",
        email: company.email ? Faker::Internet.email : nil,
        phone: company.phone ? Faker::PhoneNumber.phone_number : nil,
        website: company.website ? Faker::Internet.url : nil,
        postal_address: company.postal_address ? Faker::Address.street_address : nil,
        postal_city: company.postal_city,
        postal_code: company.postal_code,
        source_country: company.source_country,
        source_registry: company.source_registry,
        organization_form_code: company.organization_form_code,
        operating_revenue: company.operating_revenue,
        ordinary_result: company.ordinary_result,
        annual_result: company.annual_result,
        employee_count: company.employee_count,
        primary_industry_code: company.primary_industry_code,
        primary_industry_description: company.primary_industry_description
      }
    end

    # Write anonymized fixtures
    File.open(fixtures_dir.join("companies.yml"), "w") do |file|
      companies_to_anonymize.each_with_index do |attrs, index|
        file.puts "company_#{index}:"
        attrs.each do |key, value|
          if value.nil?
            file.puts "  #{key}: null"
          else
            file.puts "  #{key}: #{value.inspect}"
          end
        end
        file.puts
      end
    end

    puts "Anonymized fixtures created in spec/fixtures/anonymized/"
  end
end
