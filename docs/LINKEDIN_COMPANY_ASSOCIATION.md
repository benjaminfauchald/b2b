# LinkedIn Company Association Feature

## Overview

This feature associates unassociated people with companies based on LinkedIn company IDs, addressing the gap where people records have `linkedin_company_id` but no `company_id` association.

**Feature tracked by IDM**: `FeatureMemories::LinkedinCompanyAssociation`

## Problem Statement

- People imported from PhantomBuster have `linkedin_company_id` but no direct company association
- Companies have LinkedIn URLs with slugs (e.g., `https://no.linkedin.com/company/betonmast`)
- People have LinkedIn company IDs (e.g., `51649953`)
- Need to match these different identifier formats to create proper associations

## Solution Architecture

### Core Components

1. **LinkedinCompanyLookup Model** - Persistent lookup table for efficient company resolution
2. **LinkedinCompanySlugService** - Extracts slugs from company LinkedIn URLs
3. **LinkedinCompanyAssociationService** - Main association logic
4. **LinkedinCompanyResolver** - Multi-strategy lookup resolver
5. **Background Processing** - Sidekiq workers for scalable processing

### Data Flow

```
Step 1: Companies (linkedin_slug) → LinkedinCompanyIdPopulationService → Companies (linkedin_company_id)
Step 2: People (linkedin_company_id) → Direct Match → Companies (linkedin_company_id) → Association Success
```

## Implementation Phases

### Phase 1: Foundation & Data Normalization (Week 1)

#### LinkedinCompanyLookup Model
```ruby
class LinkedinCompanyLookup < ApplicationRecord
  belongs_to :company
  
  validates :linkedin_company_id, presence: true, uniqueness: true
  validates :confidence_score, inclusion: { in: 0..100 }
  
  scope :high_confidence, -> { where('confidence_score >= ?', 80) }
  scope :needs_refresh, -> { where('last_verified_at < ?', 7.days.ago) }
end
```

**Database Schema:**
```sql
CREATE TABLE linkedin_company_lookups (
  id BIGSERIAL PRIMARY KEY,
  linkedin_company_id VARCHAR(255) UNIQUE NOT NULL,
  company_id BIGINT REFERENCES companies(id),
  linkedin_slug VARCHAR(255),
  confidence_score INTEGER DEFAULT 100,
  last_verified_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### LinkedinCompanySlugService
```ruby
class LinkedinCompanySlugService < ApplicationService
  def initialize(batch_size: 100, **options)
    super(service_name: "linkedin_company_slug_population", **options)
    @batch_size = batch_size
  end

  def perform
    return error_result("Service disabled") unless service_active?
    
    companies_needing_slugs = Company.needs_linkedin_slug_population
    process_companies_batch(companies_needing_slugs)
  end

  private

  def extract_slug_from_url(url)
    # Extract slug from URLs like:
    # https://no.linkedin.com/company/betonmast → betonmast
    # https://www.linkedin.com/company/betonmast → betonmast
    return nil unless url.present?
    
    match = url.match(%r{linkedin\.com/company/([^/?]+)})
    match ? match[1] : nil
  end
end
```

### Phase 2: Association Engine (Week 2)

#### LinkedinCompanyAssociationService
```ruby
class LinkedinCompanyAssociationService < ApplicationService
  def initialize(batch_size: 500, **options)
    super(service_name: "linkedin_company_association", **options)
    @batch_size = batch_size
  end

  def perform
    return error_result("Service disabled") unless service_active?
    
    people_needing_association = Person.needing_company_association
    process_association_batch(people_needing_association)
  end

  private

  def process_association_batch(people)
    people.find_in_batches(batch_size: @batch_size) do |batch|
      batch.each do |person|
        associate_person_with_company(person)
      end
    end
  end

  def associate_person_with_company(person)
    return unless person.linkedin_company_id.present?
    
    company = resolver.resolve(person.linkedin_company_id)
    
    if company
      person.update!(company: company)
      audit_success(person, company)
    else
      audit_failure(person)
    end
  end

  def resolver
    @resolver ||= LinkedinCompanyResolver.new
  end
end
```

#### Background Processing
```ruby
class LinkedinCompanyAssociationWorker
  include Sidekiq::Worker
  
  sidekiq_options retry: 3, queue: :linkedin_association

  def perform(person_id = nil)
    if person_id
      person = Person.find(person_id)
      LinkedinCompanyAssociationService.new.call(person: person)
    else
      LinkedinCompanyAssociationService.new.perform
    end
  end
end
```

### Phase 3: Lookup Optimization (Week 3)

#### LinkedinCompanyResolver
```ruby
class LinkedinCompanyResolver
  def initialize
    @cache = Rails.cache
  end

  def resolve(linkedin_company_id)
    return nil unless linkedin_company_id.present?
    
    # Strategy 1: Cache lookup
    cached_company = @cache.fetch(cache_key(linkedin_company_id), expires_in: 1.hour) do
      resolve_from_strategies(linkedin_company_id)
    end
    
    cached_company
  end

  private

  def resolve_from_strategies(linkedin_company_id)
    # Strategy 1: Direct lookup table
    lookup = LinkedinCompanyLookup.find_by(linkedin_company_id: linkedin_company_id)
    return lookup.company if lookup&.company

    # Strategy 2: Direct company match
    company = Company.find_by(linkedin_company_id: linkedin_company_id)
    return company if company

    # Strategy 3: Convert ID to slug and match
    slug = LinkedinCompanyDataService.id_to_slug(linkedin_company_id)
    if slug
      company = Company.find_by(linkedin_slug: slug)
      if company
        # Update lookup table for future efficiency
        create_lookup_entry(linkedin_company_id, company, slug)
        return company
      end
    end

    # Strategy 4: Fallback matching (if enabled)
    fallback_company_matching(linkedin_company_id) if fallback_enabled?
  end

  def create_lookup_entry(linkedin_company_id, company, slug)
    LinkedinCompanyLookup.find_or_create_by(linkedin_company_id: linkedin_company_id) do |lookup|
      lookup.company = company
      lookup.linkedin_slug = slug
      lookup.confidence_score = 95
      lookup.last_verified_at = Time.current
    end
  end
end
```

### Phase 4: Error Recovery & Monitoring (Week 4)

#### Error Handling
```ruby
class LinkedinAssociationErrorHandler
  def self.handle_malformed_id(linkedin_company_id, person)
    # Log and categorize malformed IDs
    Rails.logger.warn "Malformed LinkedIn ID: #{linkedin_company_id} for person #{person.id}"
    
    # Attempt cleanup
    cleaned_id = clean_linkedin_id(linkedin_company_id)
    return cleaned_id if cleaned_id != linkedin_company_id
    
    nil
  end

  def self.handle_api_rate_limit
    # Implement exponential backoff
    delay = calculate_backoff_delay
    LinkedinCompanyAssociationWorker.perform_in(delay.seconds)
  end

  private

  def self.clean_linkedin_id(id)
    # Remove common prefixes/suffixes and invalid characters
    id.to_s.gsub(/[^0-9]/, '').presence
  end
end
```

#### Monitoring Dashboard
```ruby
class LinkedinAssociationStatus
  def self.report
    {
      processing_stats: processing_statistics,
      queue_health: queue_health_check,
      error_summary: error_analysis,
      performance_metrics: performance_summary
    }
  end

  private

  def self.processing_statistics
    {
      total_people: Person.count,
      unassociated_people: Person.needing_company_association.count,
      association_success_rate: calculate_success_rate,
      daily_processing_volume: daily_processing_count
    }
  end

  def self.queue_health_check
    {
      pending_jobs: LinkedinCompanyAssociationWorker.jobs.size,
      failed_jobs: failed_job_count,
      average_processing_time: average_job_duration,
      last_successful_run: last_successful_processing_time
    }
  end
end
```

## Service Configuration

### Association Service (Every 2 hours)
```ruby
ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_association") do |config|
  config.active = true
  config.refresh_interval_hours = 2
  config.batch_size = 500
  config.retry_attempts = 3
  config.settings = {
    "max_processing_time_minutes" => 30,
    "enable_immediate_processing" => true,
    "priority_new_imports" => true,
    "confidence_threshold" => 75,
    "enable_fallback_matching" => false
  }
end
```

### Lookup Table Refresh (Every 12 hours)
```ruby
ServiceConfiguration.find_or_create_by(service_name: "linkedin_company_slug_population") do |config|
  config.active = true
  config.refresh_interval_hours = 12
  config.batch_size = 100
  config.retry_attempts = 2
  config.settings = {
    "force_refresh_threshold_days" => 7,
    "validate_existing_slugs" => true,
    "cleanup_stale_entries" => true
  }
end
```

## Model Enhancements

### Person Model
```ruby
class Person < ApplicationRecord
  belongs_to :company, optional: true
  
  scope :needing_company_association, -> {
    where(company_id: nil)
      .where.not(linkedin_company_id: [nil, ''])
      .includes(:company)
  }
  
  scope :recently_associated, -> {
    where('updated_at > ?', 24.hours.ago)
      .where.not(company_id: nil)
  }
end
```

### Company Model
```ruby
class Company < ApplicationRecord
  has_many :people
  has_many :linkedin_company_lookups
  
  scope :with_linkedin_identifiers, -> {
    where.not(linkedin_company_id: nil)
      .or(where.not(linkedin_slug: nil))
  }
  
  scope :needs_linkedin_slug_population, -> {
    where(linkedin_slug: nil)
      .where.not(linkedin_url: nil)
      .or(where.not(linkedin_ai_url: nil))
  }
end
```

## Processing Schedule

### Automatic Processing
- **Every 2 hours**: Association processing for unassociated people
- **Every 12 hours**: Lookup table refresh and slug population  
- **Every 24 hours**: Cache cleanup and performance optimization
- **Every 7 days**: Deep maintenance and accuracy verification

### Trigger-Based Processing
- **Immediate**: New PhantomBuster imports
- **On-demand**: Manual admin requests
- **Recovery**: Failed job retries with exponential backoff

## Performance Targets

| Metric | Target | Monitoring |
|--------|--------|------------|
| Processing Time | < 2 seconds per record | Real-time tracking |
| Success Rate | 95%+ associations | Daily reports |
| Cache Hit Rate | 85%+ lookups | Redis monitoring |
| API Efficiency | < 1000 calls/day | Rate limit tracking |
| Queue Processing | < 30 minutes/batch | Sidekiq monitoring |

## Error Handling

### Common Issues & Solutions

1. **Malformed LinkedIn IDs**
   - Automatic cleanup and normalization
   - Fallback to company name matching
   - Manual review queue for edge cases

2. **Rate Limiting**
   - Exponential backoff for API calls
   - Queue prioritization for high-confidence matches
   - Circuit breaker pattern for repeated failures

3. **Memory Issues**
   - Batch processing with configurable sizes
   - Garbage collection optimization
   - Memory usage monitoring and alerts

### Recovery Mechanisms

- **Automatic Retry**: 3 attempts with exponential backoff
- **Manual Recovery**: Admin interface for failed associations
- **Rollback Support**: Ability to reverse incorrect associations
- **Audit Trail**: Complete logging for debugging and compliance

## Testing Strategy

### Test Categories

1. **Unit Tests**
   - Service classes and resolvers
   - Model scopes and validations
   - Error handling mechanisms

2. **Integration Tests**
   - End-to-end association workflows
   - Background job processing
   - Cache behavior and invalidation

3. **Performance Tests**
   - Large batch processing scenarios
   - Memory usage under load
   - Cache hit rate optimization

### Test Data

```ruby
# spec/factories/linkedin_company_lookups.rb
FactoryBot.define do
  factory :linkedin_company_lookup do
    linkedin_company_id { "51649953" }
    association :company
    linkedin_slug { "betonmast" }
    confidence_score { 95 }
    last_verified_at { 1.day.ago }
  end
end

# Test scenarios
describe LinkedinCompanyAssociationService do
  it "associates person with company via direct ID match"
  it "associates person with company via slug conversion"
  it "handles malformed LinkedIn IDs gracefully"
  it "respects confidence thresholds"
  it "processes large batches efficiently"
end
```

## Deployment Checklist

### Pre-Deployment
- [ ] Database migrations applied
- [ ] Service configurations created
- [ ] Background workers configured
- [ ] Monitoring dashboards setup
- [ ] Test data verification

### Post-Deployment
- [ ] Processing queue health check
- [ ] Success rate monitoring
- [ ] Error rate analysis
- [ ] Performance metrics validation
- [ ] Cache efficiency verification

## Monitoring & Alerting

### Key Metrics
- Association success rate (target: 95%+)
- Processing queue depth
- Error categorization and frequency
- API rate limit usage
- Cache hit rates

### Alert Conditions
- Success rate below 90%
- Queue depth above 5000 jobs
- Error rate above 5%
- Processing time above 5 seconds/record
- Memory usage above 80%

## Future Enhancements

### Planned Improvements
1. **Machine Learning**: Fuzzy matching for company names
2. **Real-time Processing**: WebSocket-based live updates
3. **Advanced Analytics**: Association confidence scoring
4. **API Integration**: Direct LinkedIn Company API integration
5. **Automated Validation**: Periodic accuracy verification

### Scalability Considerations
- Horizontal scaling with multiple workers
- Database sharding for large datasets
- Redis cluster for cache distribution
- API rate limiting and quotas
- Monitoring and alerting automation

## Support & Troubleshooting

### Common Commands
```bash
# Check association status
rails runner "puts LinkedinAssociationStatus.report"

# Process specific person
LinkedinCompanyAssociationWorker.perform_async(person_id)

# Refresh lookup table
LinkedinCompanySlugService.new.perform

# Clear cache
Rails.cache.clear
```

### Log Analysis
```bash
# Check processing logs
tail -f log/production.log | grep LinkedinCompanyAssociation

# Monitor queue
bundle exec sidekiq-web

# Check database stats
rails dbconsole
```

---

**Last Updated**: July 2025  
**Version**: 1.0  
**Maintainer**: Development Team