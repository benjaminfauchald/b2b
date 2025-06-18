# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Rails Server
- `PORT=3000 rails server` - Start Rails server on port 3000 (nginx proxies from HTTPS port 443)
- `rails console` - Open Rails console
- **Important**: Use port 3000 for production (nginx SSL proxy setup) and bind to 0.0.0.0 for external interface access

### Background Jobs
- `bundle exec sidekiq` - Start Sidekiq worker for all queues
- `bundle exec sidekiq -q [queue_name]` - Start worker for specific queue (e.g., brreg_migration, company_financials)

### Development Quality Checks
- `./bin/check` - **Run this before every commit** (RuboCop + tests + security check)
- `bundle exec rubocop` - Run linting only
- `bundle exec rubocop -a` - Auto-fix safe linting issues
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/path/to/file_spec.rb` - Run specific test file
- `bundle exec guard` - Auto-run tests on file changes
- `bundle exec brakeman` - Security analysis

### Pre-Commit Hooks
- **Automatic**: Pre-commit hooks run RuboCop and related tests on staged files
- **Manual bypass**: `git commit --no-verify` (not recommended)
- **Best practice**: Always run `./bin/check` before committing

### Database
- `rails db:migrate` - Run migrations
- `rails db:seed` - Run seeds
- `rails db:reset` - Reset database (drop, create, migrate, seed)

### Service Management
- `rake service_audit:refresh_needed` - Check which services need refresh
- `rake financials:sample` - Update financial data for sample companies
- `rake financials:queue[count]` - Queue companies for financial updates
- `rake domain_testing:sample` - Test DNS for sample domains
- `rake domain_testing:queue[count]` - Queue domains for DNS testing

### Kafka (Optional)
- Kafka is conditionally enabled via `KAFKA_ENABLED=true` environment variable
- `docker-compose up kafka` - Start Kafka broker
- Consumers: `bundle exec karafka consumer` - Start Kafka consumers

## Production Configuration

### Database
- **Production Database**: app.connectica.no

## Architecture Overview

### Service-Oriented Architecture
This application follows a service-oriented pattern with the following key components:

**Services** (`app/services/`):
- All services inherit from `ApplicationService`
- Services implement a `perform` method and are called via `.call`
- Built-in audit logging and error handling
- Example: `CompanyFinancialsService`, `DomainTestingService`

**Workers** (`app/workers/`):
- Sidekiq background job processors
- Handle async processing of services
- Example: `CompanyFinancialsWorker`, `DomainTestingWorker`

**Consumers** (`app/consumers/`) - Optional Kafka Integration:
- Karafka-based Kafka message consumers
- Process events from Kafka topics
- Example: `FinancialsConsumer`, `DomainTestingConsumer`

### Service Audit System
**Core Concept**: All service operations are automatically tracked via `ServiceAuditLog` model.

**Key Models**:
- `ServiceAuditLog` - Tracks all service executions with timing, status, and metadata
- `ServiceConfiguration` - Configures service refresh intervals and activation
- `LatestServiceRun` - Optimized view of most recent service runs
- Models include `ServiceAuditable` concern for automatic audit tracking

**Usage Patterns**:
```ruby
# In services
audit_service_operation(service_name, operation_type: 'process') do |audit_log|
  # Service logic here
end

# Check if record needs service
record.needs_service?('service_name')

# Get records needing a service
Model.needs_service('service_name')
```

### Data Models
**Core Models**:
- `User` - Devise authentication with admin roles
- `Domain` - Domain records with DNS testing capabilities
- `Company` - Company records with financial data integration
- `Brreg` - Norwegian business register data

**Service Integration**:
All auditable models include `ServiceAuditable` concern, providing:
- Automatic audit logging for create/update operations
- Service refresh timing logic
- Batch processing capabilities

### Background Processing
**Sidekiq Queues**:
- Default queue for general jobs
- `brreg_migration` - Brreg data migration
- `company_financials` - Financial data updates
- Domain testing queues

### External Integrations
**Optional Kafka Integration**:
- Event-driven architecture for service communication
- Topics: `company_financials`, `domain_testing`, `brreg_migration`
- Dead letter queues for failed message processing

### Configuration
**Environment-Based**:
- Service auditing controlled via `config.service_auditing_enabled`
- Automatic auditing via `config.automatic_auditing_enabled`
- Kafka conditionally enabled via `KAFKA_ENABLED` environment variable

**Service Configuration**:
- Each service can be configured via `ServiceConfiguration` model
- Controls refresh intervals and service activation
- Accessed in services via `configuration` method

### Testing Strategy
**RSpec with:**
- FactoryBot for test data
- Shoulda matchers for model testing
- Service-specific test helpers in `spec/support/`
- Integration tests for complete service workflows

**Key Test Files**:
- Service specs test business logic
- Worker specs test background job processing
- Consumer specs test Kafka message handling
- Integration specs test end-to-end workflows

### Development Workflow
1. Services are the primary business logic containers
2. Workers handle async processing via Sidekiq
3. Audit logs automatically track all service operations
4. Rake tasks provide operational commands for service management
5. Guard enables auto-testing during development

### File Organization
- `app/services/` - Business logic services
- `app/workers/` - Background job processors
- `app/consumers/` - Kafka message consumers (optional)
- `lib/tasks/` - Operational rake tasks
- `spec/` - RSpec test suite
- `config/initializers/kafka.rb` - Kafka configuration (conditional)
- `config/karafka.rb` - Kafka consumer configuration