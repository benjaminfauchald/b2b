# B2B Service Platform

## Services Overview

### Brreg Migration Service
- **Command**: `bundle exec sidekiq -q brreg_migration`
- **Purpose**: Processes and migrates company data from Brreg (Norwegian Business Register)

### User Enhancement Service
- **Command**: `rake service_audit:run_service[user_enhancement]`
- **Purpose**: Enhances user data with email validation and provider classification

### Domain Testing Service
- **Command**: `rake service_audit:run_service[domain_testing]`
- **Purpose**: Tests domain DNS records and connectivity

### Domain A Record Testing Service
- **Command**: `rake service_audit:run_service[domain_a_record_testing]`
- **Purpose**: Tests WWW A records for domains

### Automatic Audit Service
- **Command**: `rake service_audit:run_service[automatic_audit]`
- **Purpose**: Tracks create/update/destroy operations in the system

## Service Management

### Check Service Status
```bash
rake service_audit:refresh_needed
```

### Start Rails Server
```bash
rails server -p 4001
```

### Start Sidekiq Worker
```bash
bundle exec sidekiq -q [queue_name]
```

## Environment Setup
- All credentials are managed via environment variables
- Shell configuration uses ZSH (`.zshrc`)
