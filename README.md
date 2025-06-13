# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

# B2B Project

This project manages company data with a focus on Norwegian (BRREG) and international companies, financial data, and LinkedIn integration. It uses Rails, PostgreSQL, and includes robust data migration and backup tooling.

## Key Rake Tasks

### Domain Service Tasks
- **domain:test_dns**
  - Runs the `DomainTestingService` for all applicable domains (tests DNS records).
  - Usage: `rails domain:test_dns`

- **domain:test_a_record**
  - Runs the `DomainARecordTestingService` for all applicable domains (tests A records).
  - Usage: `rails domain:test_a_record`

- **domain:test_successful**
  - Runs the `DomainSuccessfulTestService` for all domains where both DNS and WWW tests are successful.
  - Usage: `rails domain:test_successful`

### Data Migration
- **brreg:migrate_to_companies**
  - Migrates data from the `brreg` table (Norwegian, BRREG-style columns) to the `companies` table (English, international schema).
  - Handles column mapping, batching, error handling, progress reporting, duplicate handling, and resumability.
  - Usage: `rails brreg:migrate_to_companies`

- **brreg:resume_migrate_to_companies**
  - Resumes the migration from the last processed record if interrupted.
  - Usage: `rails brreg:resume_migrate_to_companies`

### Backup and Restore
- **brreg:backup_development**
  - Backs up the `brreg` and `companies` tables in the development database to `backups/`.
  - Usage: `rails brreg:backup_development`

- **brreg:restore_development**
  - Restores the `brreg` and `companies` tables in the development database from a selected backup file.
  - Usage: `rails brreg:restore_development`

- **brreg:backup_production**
  - Backs up the `brreg` and `companies` tables in the production database to `backups/`.
  - Usage: `rails brreg:backup_production`

- **brreg:restore_production**
  - Restores the `brreg` and `companies` tables in the production database from a selected backup file.
  - Usage: `rails brreg:restore_production`

- **brreg:backup_test**
  - Backs up the `brreg` and `companies` tables in the test database to `backups/`.
  - Usage: `rails brreg:backup_test`

- **brreg:restore_test**
  - Restores the `brreg` and `companies` tables in the test database from a selected backup file.
  - Usage: `rails brreg:restore_test`

## Best Practices
- Always run a backup before any data migration or destructive operation.
- Use the resume task if a migration is interrupted.
- Test migrations in development before running in production.

## Project Structure
- `app/models/brreg.rb` — Model for the Norwegian BRREG-style table
- `app/models/company.rb` — Model for the international companies table
- `lib/tasks/brreg_to_companies.rake` — All migration, backup, and restore tasks
- `lib/tasks/domain_services.rake` — All domain service tasks

## Contact
For questions or support, contact the project maintainer.
