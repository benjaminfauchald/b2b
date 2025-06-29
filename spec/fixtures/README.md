# Test Fixtures

This directory contains test fixtures generated from production data for realistic testing scenarios.

## Generated Fixtures

### companies.yml
Real company data with various states:
- `norwegian_company_complete` - Company with all data (website, LinkedIn, financials)
- `norwegian_company_no_website` - High revenue company without website (good for web discovery testing)
- `norwegian_company_no_financials` - Company missing financial data
- `swedish_company_high_revenue` - Swedish company with high revenue
- `company_minimal_data` - Edge case with minimal data
- `company_with_special_chars` - Company name with special characters

### service_audit_logs.yml
Real audit log entries:
- `successful_financial_audit` - Successful financial data update
- `failed_web_discovery` - Failed web discovery attempt
- `successful_linkedin_discovery` - Successful LinkedIn profile discovery

### service_configurations.yml
Active service configurations for all services

### domains.yml
Domain records with various DNS states (empty if no domains in DB)

## Usage

### In RSpec Tests

```ruby
require 'rails_helper'

RSpec.describe Company, type: :model do
  fixtures :companies, :service_audit_logs
  
  it "uses fixture data" do
    company = companies(:norwegian_company_no_website)
    expect(company.operating_revenue).to be > 10_000_000
    expect(company.website).to be_nil
  end
end
```

### Regenerating Fixtures

To regenerate fixtures from current database:
```bash
bundle exec rake fixtures:generate
```

To generate anonymized fixtures:
```bash
bundle exec rake fixtures:anonymize
```

### Loading Test Data

To seed the database with test data matching fixture patterns:
```bash
rails db:seed:test_data
```

## Fixture Scenarios

Use the `FixtureScenarios` module for common test setups:

```ruby
describe "web discovery" do
  include FixtureScenarios
  
  before do
    load_web_discovery_scenario
  end
  
  it "processes companies needing discovery" do
    expect(@companies_needing_discovery).not_to be_empty
  end
end
```

## Best Practices

1. **Keep fixtures minimal** - Only include data needed for tests
2. **Use factories for dynamic data** - Fixtures for reference data
3. **Anonymize sensitive data** - Use the anonymize task
4. **Document edge cases** - Explain why specific fixtures exist
5. **Version fixtures** - Track changes over time

## Maintenance

Fixtures should be regenerated when:
- Database schema changes significantly
- New edge cases are discovered in production
- Test coverage needs expansion
- Performance testing requires larger datasets