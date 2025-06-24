# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Mentorship

### Learning Ruby on Rails the Right Way
- Always prioritize understanding the Rails conventions and idiomatic Ruby
- Break down complex problems into smaller, manageable service objects
- Focus on writing clean, readable code that follows the Single Responsibility Principle
- Learn to leverage Rails built-in tools and generators instead of reinventing the wheel
- Practice using Rails conventions like RESTful routes, strong parameters, and model validations
- Study and implement service objects to keep controllers thin and business logic organized
- Embrace test-driven development (TDD) to write more reliable and maintainable code
- Learn to use Rails console (`./bin/rails console`) for quick debugging and exploration
- Always ask "What would a senior Rails developer do?" when designing solutions
- Read the Rails guides, source code, and follow best practices from experienced developers
- Understand the importance of separation of concerns in Rails applications
- Practice refactoring and continuously improve your code quality
- Learn to use Ruby's powerful metaprogramming features judiciously
- Familiarize yourself with common Rails design patterns and architectural approaches

## Development Commands

### Rails Server
- `./bin/rake restart` - **ALWAYS USE THIS** to restart Rails server (kills old processes and starts fresh)
- `./bin/rake kill` - Kill any Rails server running on port 3000
- `./bin/rails console` - Open Rails console
- **CRITICAL**: Always use `./bin/rake restart` when testing new code to ensure no cached code is running
- **Important**: Use port 3000 for production (nginx SSL proxy setup) and bind to 0.0.0.0 for external interface access
- Start rails server automatically when you expect user to test using `./bin/rake restart`
- **Note**: Always use `./bin/rails` or `bundle exec rails` instead of just `rails` to avoid rbenv issues

### Environment Variables
- All environment variables for Rails is in `.env.local`

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
- `./bin/rails db:migrate` - Run migrations
- `./bin/rails db:seed` - Run seeds
- `./bin/rails db:reset` - Reset database (drop, create, migrate, seed)

### Service Management
- `./bin/rake service_audit:refresh_needed` - Check which services need refresh
- `./bin/rake financials:sample` - Update financial data for sample companies
- `./bin/rake financials:queue[count]` - Queue companies for financial updates
- `./bin/rake domain_testing:sample` - Test DNS for sample domains
- `./bin/rake domain_testing:queue[count]` - Queue domains for DNS testing

### Kafka (Optional)
- Kafka is conditionally enabled via `KAFKA_ENABLED=true` environment variable
- `docker-compose up kafka` - Start Kafka broker
- Consumers: `bundle exec karafka consumer` - Start Kafka consumers

## Production Configuration

### Database
- **Production Database**: app.connectica.no

## Architecture Overview

### Service-Oriented Architecture
This application follows a **standardized service-oriented pattern** documented in `docs/SERVICE_ARCHITECTURE_STANDARD.md`.

**📋 IMPORTANT**: All new services MUST follow the architecture standard. See documentation:
- `docs/SERVICE_ARCHITECTURE_STANDARD.md` - Complete standard requirements
- `docs/DOMAIN_SERVICES_IMPLEMENTATION.md` - Implementation examples
- `docs/service_architecture/SERVICE_TEMPLATE.md` - Template for new services

**Services** (`app/services/`):
- All services inherit from `ApplicationService`
- Services implement a `call` method (not `perform`)
- Handle both individual records and batch processing
- Built-in audit logging via `ServiceAuditLog`
- Example: `DomainTestingService`, `DomainMxTestingService`

**Workers** (`app/workers/`):
- Lightweight Sidekiq job processors
- Only handle job execution and error logging
- Delegate all business logic to services
- Follow exact pattern from architecture standard
- Example: `DomainDnsTestingWorker`, `DomainMxTestingWorker`

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
- `app/services/` - Business logic services (must follow architecture standard)
- `app/workers/` - Background job processors (must follow architecture standard)
- `app/consumers/` - Kafka message consumers (optional)
- `lib/tasks/` - Operational rake tasks
- `spec/` - RSpec test suite
- `docs/` - Architecture documentation and standards
- `config/initializers/kafka.rb` - Kafka configuration (conditional)
- `config/karafka.rb` - Kafka consumer configuration