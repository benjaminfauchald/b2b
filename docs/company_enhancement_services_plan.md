# Company Enhancement Services Implementation Plan

## Overview
Implement four enhancement services for companies, mirroring the domain testing service architecture:
1. **Financial Data Service** - Fetch and update company financial information
2. **Web Pages Discovery Service** - Find and catalog company websites
3. **LinkedIn Page Discovery Service** - Locate and verify company LinkedIn profiles
4. **Employee Discovery Service** - Find and track company employees

## Architecture Overview

### Service Layer Architecture
```
├── app/services/
│   ├── company_financial_data_service.rb
│   ├── company_web_discovery_service.rb
│   ├── company_linkedin_discovery_service.rb
│   └── company_employee_discovery_service.rb
│
├── app/workers/
│   ├── company_financial_data_worker.rb
│   ├── company_web_discovery_worker.rb
│   ├── company_linkedin_discovery_worker.rb
│   └── company_employee_discovery_worker.rb
│
├── app/controllers/
│   └── companies_controller.rb (enhanced with queue actions)
│
├── app/components/
│   ├── company_service_queue_button_component.rb
│   ├── company_service_stats_card_component.rb
│   └── company_enhancement_dashboard_component.rb
│
└── app/views/
    └── companies/
        ├── index.html.erb (enhanced dashboard)
        └── show.html.erb (individual service triggers)
```

## Database Schema Updates

### 1. Service Configuration Seeds
```ruby
# db/seeds/company_services.rb
[
  {
    service_name: 'company_financial_data',
    enabled: true,
    refresh_interval_days: 30,
    description: 'Fetches financial data from public registries'
  },
  {
    service_name: 'company_web_discovery',
    enabled: true,
    refresh_interval_days: 90,
    description: 'Discovers company websites and web presence'
  },
  {
    service_name: 'company_linkedin_discovery',
    enabled: true,
    refresh_interval_days: 60,
    description: 'Finds and verifies company LinkedIn profiles'
  },
  {
    service_name: 'company_employee_discovery',
    enabled: true,
    refresh_interval_days: 45,
    description: 'Discovers employees from various sources'
  }
]
```

### 2. Company Model Enhancements
Additional fields may be needed:
- `financial_data_updated_at`
- `web_pages` (JSON/JSONB)
- `linkedin_profiles` (JSON/JSONB)
- `discovered_employees_count`

## Component Structure

### 1. CompanyServiceQueueButtonComponent
```ruby
# Similar to ServiceQueueButtonComponent but for companies
# Props:
# - service_name: String
# - title: String
# - icon: String
# - action_path: String
# - queue_name: String
# - company_scope: ActiveRecord::Relation (optional)
```

### 2. CompanyServiceStatsCardComponent
```ruby
# Display statistics for each service
# Props:
# - service_name: String
# - processed_count: Integer
# - pending_count: Integer
# - failed_count: Integer
# - last_run_at: DateTime
```

### 3. CompanyEnhancementDashboardComponent
```ruby
# Main dashboard component that orchestrates all services
# Props:
# - companies: ActiveRecord::Relation
# - queue_stats: Hash
# - service_stats: Hash
```

## Controller Actions

### CompaniesController Enhancements
```ruby
class CompaniesController < ApplicationController
  # Existing actions...
  
  # Queue all companies for a specific service
  def queue_financial_data
  def queue_web_discovery
  def queue_linkedin_discovery
  def queue_employee_discovery
  
  # Queue individual company for services
  def queue_single_financial_data
  def queue_single_web_discovery
  def queue_single_linkedin_discovery
  def queue_single_employee_discovery
  
  # Get queue status
  def enhancement_queue_status
end
```

## Service Implementation Pattern

Each service follows the same pattern:
```ruby
class CompanyFinancialDataService < ApplicationService
  def initialize(company)
    @company = company
  end

  def perform
    audit_service_operation('company_financial_data') do |audit_log|
      # 1. Check if service is needed
      return success_result('Already up to date') unless needs_update?
      
      # 2. Fetch data from external source
      data = fetch_financial_data
      
      # 3. Update company record
      update_company(data)
      
      # 4. Return result
      success_result('Financial data updated', data)
    end
  end
  
  private
  
  def needs_update?
    @company.needs_service?('company_financial_data')
  end
  
  def fetch_financial_data
    # Implementation specific to each service
  end
  
  def update_company(data)
    # Update logic
  end
end
```

## UI/UX Design with Tailwind & Flowbite

### 1. Companies Index Enhancement
```erb
<!-- Company Enhancement Dashboard -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
  <!-- Service Queue Buttons -->
  <%= render CompanyServiceQueueButtonComponent.new(
    service_name: "company_financial_data",
    title: "Financial Data",
    icon: "💰",
    action_path: queue_financial_data_companies_path,
    queue_name: "company_financial_data"
  ) %>
  <!-- Repeat for other services -->
</div>

<!-- Statistics Grid -->
<div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
  <!-- Service stats cards -->
</div>

<!-- Companies Table with Enhancement Status -->
<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <!-- Table with service status indicators -->
  </table>
</div>
```

### 2. Company Show Page Enhancements
```erb
<!-- Individual Service Triggers -->
<div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6 mb-6">
  <h3 class="text-lg font-semibold mb-4">Enhancement Services</h3>
  <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
    <!-- Individual service trigger buttons -->
  </div>
</div>
```

## Testing Strategy

### 1. Service Tests
```ruby
# spec/services/company_financial_data_service_spec.rb
RSpec.describe CompanyFinancialDataService do
  describe '#perform' do
    context 'when service is needed' do
      it 'fetches and updates financial data'
      it 'creates audit log with success status'
      it 'updates financial_data_updated_at timestamp'
    end
    
    context 'when service is not needed' do
      it 'returns early without fetching data'
      it 'creates audit log with skipped status'
    end
    
    context 'when external API fails' do
      it 'handles errors gracefully'
      it 'creates audit log with error status'
    end
  end
end
```

### 2. Worker Tests
```ruby
# spec/workers/company_financial_data_worker_spec.rb
RSpec.describe CompanyFinancialDataWorker do
  describe '#perform' do
    it 'calls the service with correct company'
    it 'handles non-existent company IDs'
    it 'respects retry configuration'
  end
end
```

### 3. Controller Tests
```ruby
# spec/controllers/companies_controller_spec.rb
RSpec.describe CompaniesController do
  describe 'POST #queue_financial_data' do
    it 'queues eligible companies for processing'
    it 'returns queue statistics'
    it 'requires authentication'
    it 'checks service configuration'
  end
  
  describe 'POST #queue_single_financial_data' do
    it 'queues individual company'
    it 'creates audit log'
    it 'returns job details'
  end
end
```

### 4. Component Tests
```ruby
# spec/components/company_service_queue_button_component_spec.rb
RSpec.describe CompanyServiceQueueButtonComponent do
  it 'displays service title and icon'
  it 'shows pending count'
  it 'disables when service is inactive'
  it 'triggers correct action on click'
end
```

### 5. Integration Tests
```ruby
# spec/features/company_enhancement_dashboard_spec.rb
RSpec.feature 'Company Enhancement Dashboard' do
  scenario 'User queues companies for financial data update' do
    # Full user flow test
  end
end
```

## Implementation Phases

### Phase 1: Foundation (Week 1)
1. Create service configuration seeds
2. Implement base service class pattern
3. Create first service (Financial Data) with tests
4. Set up workers and background job infrastructure

### Phase 2: UI Components (Week 2)
1. Create ViewComponents with tests
2. Enhance companies controller with queue actions
3. Build enhancement dashboard
4. Add individual company triggers

### Phase 3: Additional Services (Week 3)
1. Implement Web Discovery Service
2. Implement LinkedIn Discovery Service
3. Implement Employee Discovery Service
4. Add comprehensive error handling

### Phase 4: Polish & Optimization (Week 4)
1. Add batch processing optimizations
2. Implement rate limiting for external APIs
3. Add detailed logging and monitoring
4. Create admin interface for service management

## Configuration & Environment Variables

```yaml
# config/application.yml
company_services:
  financial_data:
    api_endpoint: <%= ENV['BRREG_API_ENDPOINT'] %>
    api_key: <%= ENV['BRREG_API_KEY'] %>
    rate_limit: 100
  web_discovery:
    search_engine_api: <%= ENV['SEARCH_API_KEY'] %>
    rate_limit: 50
  linkedin_discovery:
    api_endpoint: <%= ENV['LINKEDIN_API_ENDPOINT'] %>
    rate_limit: 30
  employee_discovery:
    sources: ['linkedin', 'company_websites', 'public_registries']
    rate_limit: 20
```

## Success Metrics
1. Service execution time < 5 seconds per company
2. Success rate > 95% for each service
3. Queue processing throughput > 100 companies/minute
4. UI response time < 200ms for dashboard
5. Test coverage > 90% for all new code

## Next Steps
1. Review and approve the plan
2. Set up test infrastructure
3. Begin TDD implementation of the first service
4. Iterate based on feedback