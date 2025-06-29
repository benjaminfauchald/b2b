# Test data seeder using fixture patterns
# Run with: rails db:seed:test_data

puts "🌱 Seeding test data based on fixture patterns..."

# Service Configurations
puts "Creating service configurations..."
%w[
  company_financial_data
  company_web_discovery
  company_linkedin_discovery
  company_employee_discovery
  domain_testing
  person_profile_extraction
].each do |service_name|
  ServiceConfiguration.find_or_create_by(service_name: service_name) do |config|
    config.active = true
    config.refresh_interval_hours = 720
    config.batch_size = 100
    config.retry_attempts = 3
    config.depends_on_services = []
    config.settings = {}
  end
end

# Norwegian Companies
puts "Creating Norwegian companies..."
10.times do |i|
  Company.create!(
    registration_number: "NO#{900000 + i}",
    company_name: "Norsk Testselskap #{i + 1} AS",
    source_country: "NO",
    source_registry: "brreg",
    organization_form_code: "AS",
    organization_form_description: "Aksjeselskap",
    operating_revenue: 5_000_000 + (i * 5_000_000),
    ordinary_result: i.even? ? 500_000 + (i * 100_000) : nil,
    annual_result: i.even? ? 400_000 + (i * 80_000) : nil,
    postal_city: ["OSLO", "BERGEN", "TRONDHEIM", "STAVANGER"][i % 4],
    postal_code: "#{i + 1}000",
    website: i < 3 ? "https://testselskap#{i}.no" : nil,
    email: i < 5 ? "post@testselskap#{i}.no" : nil,
    phone: "#{22 + i} #{10 + i} #{20 + i} #{30 + i}",
    primary_industry_code: ["68.209", "70.22", "62.01", "46.69"][i % 4],
    employee_count: 5 + (i * 3)
  )
end

# Swedish Companies
puts "Creating Swedish companies..."
5.times do |i|
  Company.create!(
    registration_number: "SE#{556000 + i}",
    company_name: "Svensk Testbolag #{i + 1} AB",
    source_country: "SE",
    source_registry: "bolagsverket",
    organization_form_code: "AB",
    organization_form_description: "Aktiebolag",
    operating_revenue: 10_000_000 + (i * 10_000_000),
    ordinary_result: 1_000_000 + (i * 200_000),
    annual_result: 800_000 + (i * 150_000),
    postal_city: ["STOCKHOLM", "GÖTEBORG", "MALMÖ"][i % 3],
    postal_code: "#{i + 1}#{i + 1}#{i + 1} #{i + 1}#{i + 1}",
    website: i < 2 ? "https://testbolag#{i}.se" : nil,
    linkedin_url: i == 0 ? "https://linkedin.com/company/testbolag#{i}" : nil
  )
end

# Danish Companies
puts "Creating Danish companies..."
3.times do |i|
  Company.create!(
    registration_number: "DK#{30000000 + i}",
    company_name: "Dansk Testvirksomhed #{i + 1} ApS",
    source_country: "DK",
    source_registry: "cvr",
    organization_form_code: "ApS",
    organization_form_description: "Anpartsselskab",
    operating_revenue: 15_000_000 + (i * 5_000_000),
    postal_city: ["KØBENHAVN", "AARHUS", "ODENSE"][i],
    postal_code: "#{i + 1}000"
  )
end

# Create Service Audit Logs
puts "Creating service audit logs..."
Company.limit(5).each do |company|
  # Financial data audit
  if company.ordinary_result.present?
    ServiceAuditLog.create!(
      auditable: company,
      service_name: "company_financials",
      operation_type: "update",
      status: ServiceAuditLog::STATUS_SUCCESS,
      table_name: "companies",
      record_id: company.id.to_s,
      columns_affected: ["ordinary_result", "annual_result", "operating_revenue"],
      metadata: { source: "brreg_api", year: 2023 },
      started_at: 2.hours.ago,
      completed_at: 1.hour.ago
    )
  end
  
  # Web discovery audit
  if company.website.present?
    ServiceAuditLog.create!(
      auditable: company,
      service_name: "company_web_discovery",
      operation_type: "discover",
      status: ServiceAuditLog::STATUS_SUCCESS,
      table_name: "companies",
      record_id: company.id.to_s,
      columns_affected: ["website", "web_pages"],
      metadata: { 
        pages_found: 3,
        confidence_scores: [80, 75, 70],
        search_queries_used: 2
      },
      started_at: 3.hours.ago,
      completed_at: 2.hours.ago
    )
  end
end

# Create some failed audits
Company.where(website: nil).limit(2).each do |company|
  ServiceAuditLog.create!(
    auditable: company,
    service_name: "company_web_discovery",
    operation_type: "discover",
    status: ServiceAuditLog::STATUS_FAILED,
    table_name: "companies",
    record_id: company.id.to_s,
    columns_affected: [],
    error_message: "No websites found for company",
    metadata: { pages_found: 0 },
    started_at: 1.hour.ago,
    completed_at: 30.minutes.ago
  )
end

# Create test domains
puts "Creating test domains..."
%w[example.no testselskap.no bedrift.se virksomhed.dk test.com].each do |domain_name|
  Domain.create!(
    domain: domain_name,
    www: [true, false].sample,
    mx: [true, false, nil].sample,
    a_record_ip: [true, false].sample ? "192.168.1.#{rand(1..255)}" : nil
  )
end

puts "✅ Test data seeding complete!"
puts "Companies created: #{Company.count}"
puts "  - Norwegian: #{Company.where(source_country: 'NO').count}"
puts "  - Swedish: #{Company.where(source_country: 'SE').count}"
puts "  - Danish: #{Company.where(source_country: 'DK').count}"
puts "Service Audit Logs: #{ServiceAuditLog.count}"
puts "Domains: #{Domain.count}"