# Integrated Development Memory (IDM) System

## Overview

The Integrated Development Memory (IDM) system is a universal code-integrated documentation framework that provides a single source of truth for ALL feature development - not just services. It tracks UI components, API endpoints, models, migrations, integrations, and any other type of feature. The IDM replaces the old file-based Feature Memory system with a Ruby DSL that lives alongside your code.

## Key Benefits

1. **Single Source of Truth**: All feature documentation lives in one Ruby class file
2. **Code Integration**: Documentation is part of the codebase, not separate markdown files
3. **Automatic Tracking**: Progress updates can be logged programmatically during development
4. **AI-Friendly**: Structured data that AI agents can easily read and update
5. **Human-Readable**: Exports to markdown for easy reading and sharing
6. **Version Controlled**: Changes tracked with your code in git

## Quick Start

### 1. Generate a New Feature Memory

```bash
rails generate feature_memory feature_name "Description of the feature"
```

This creates `app/services/feature_memories/feature_name.rb` with a template structure.

### 2. Fill in Requirements

Edit the generated file to add specific requirements:

```ruby
class FeatureMemories::YourFeature < ApplicationFeatureMemory
  feature_spec do
    description "Your feature description"
    requested_by "@username"
    created_at "2025-01-06"
    
    requirements do
      input_fields field1: "value1", field2: "value2"
      output "Expected output format"
      queue_system :sidekiq  # or :none
      ui_location :page_location
      dependencies ["gem1", "service1"]
    end
    
    test_data do
      test_id 12345
      test_url "https://example.com"
      expected_result "Expected outcome"
    end
  end
end
```

### 3. Track Implementation Progress

Update the implementation log as you work:

```ruby
implementation_log do
  step "2025-01-06 10:00" do
    action "Created service structure"
    decision "Used specific pattern because..."
    code_ref "app/services/my_service.rb:1-50"
    test_ref "spec/services/my_service_spec.rb"
    status :completed
  end
  
  step "2025-01-06 11:00" do
    action "Implementing authentication"
    challenge "API requires special headers"
    solution "Store credentials in Rails credentials"
    status :in_progress
  end
end
```

### 4. Document Issues and Solutions

As you encounter problems, document them:

```ruby
troubleshooting do
  issue "Error 429: Rate limit exceeded" do
    cause "Too many requests in short time"
    solution "Add exponential backoff"
    code_example "sleep(2 ** retry_count)"
    prevention "Implement request queuing"
  end
end
```

### 5. Track Performance Metrics

```ruby
performance_metrics do
  processing_time "2-5 seconds per record"
  memory_usage "50MB average"
  success_rate "95%"
  throughput "100 records/minute"
end
```

## Planning Features with IDM

IDM now includes a built-in planning system that works like a todo list. You document your implementation plan BEFORE starting work, then update task statuses as you progress.

### Creating a Plan

```ruby
class FeatureMemories::MyNewFeature < ApplicationFeatureMemory
  implementation_plan do
    task "Research existing patterns and dependencies" do
      priority :high
      estimated_time "30 minutes"
      tags :research, :planning
    end
    
    task "Implement core functionality" do
      priority :high
      estimated_time "2 hours"
      dependencies ["task_id_from_above"]
      assignee "@developer"
    end
    
    task "Write comprehensive tests" do
      priority :high
      estimated_time "1 hour"
      tags :testing
    end
  end
end
```

### Managing Tasks

```ruby
memory = ApplicationFeatureMemory.find('my_feature')

# Add a new task dynamically
task_id = memory.add_task("Handle edge case for empty input", 
                          priority: :medium,
                          estimated_time: "20 minutes")

# Update task status
memory.update_task(task_id, status: :in_progress)
memory.update_task(task_id, status: :completed, notes: "Added validation")

# Check plan status
status = memory.plan_status
# => { total: 5, pending: 2, in_progress: 1, completed: 2, completion_percentage: 40.0 }

# Get current tasks
memory.current_tasks  # Returns all in_progress tasks

# Get next task to work on
memory.next_task      # Returns first pending task
```

### Task Statuses

- `:pending` - Not yet started (default)
- `:in_progress` - Currently being worked on
- `:completed` - Finished successfully
- `:blocked` - Cannot proceed due to dependency or issue
- `:cancelled` - No longer needed

## Usage in Code

### Access Feature Memory

```ruby
# From anywhere in the application
memory = ApplicationFeatureMemory.find('feature_name')
```

### Log Decisions During Development

The IDM system is available in all major base classes:

```ruby
# In Services
class MyService < ApplicationService
  def perform
    feature_memory(:my_feature) do
      log_decision "Using approach X because Y"
    end
  end
end

# In Controllers
class UsersController < ApplicationController
  def update
    feature_memory(:user_management) do
      log_decision "Added soft delete instead of hard delete"
    end
  end
end

# In Models
class User < ApplicationRecord
  feature_memory(:user_authentication) do
    log_decision "Using bcrypt for password hashing"
  end
end

# In ViewComponents
class NavbarComponent < ViewComponent::Base
  def initialize
    feature_memory(:responsive_navigation) do
      log_decision "Using mobile-first design with hamburger menu"
    end
  end
end

# In Jobs
class EmailSenderJob < ApplicationJob
  def perform
    feature_memory(:email_queue_system) do
      log_challenge "Rate limiting issues", solution: "Implement exponential backoff"
    end
  end
end
```

### Quick Logging

```ruby
memory = ApplicationFeatureMemory.find('my_feature')
memory.log_step("Completed user authentication", 
                status: :completed,
                code_ref: "app/controllers/auth_controller.rb:25")
```

## Available Commands

### View Status

```bash
# Single feature
rails feature_memory:status feature_name

# All features
rails feature_memory:status
```

### Export to Markdown

```bash
rails feature_memory:export feature_name
# Creates tmp/feature_memory_feature_name_timestamp.md
```

### Resume Work

```bash
rails feature_memory:resume feature_name
# Shows current status and last action
```

### Generate Report

```bash
rails feature_memory:report
# Shows status of all features
```

## Implementation Log Status Values

- `:planning` - Initial planning phase
- `:in_progress` - Currently being worked on
- `:completed` - Step finished successfully
- `:failed` - Step failed or blocked
- `:paused` - Temporarily halted

## Best Practices

1. **Update as You Code**: Don't wait until the end to update the implementation log
2. **Be Specific**: Include file paths and line numbers in code references
3. **Document Decisions**: Explain WHY you chose a particular approach
4. **Track Problems**: Every challenge should have a documented solution
5. **Test References**: Link implementation steps to their tests

## Migration from Old System

If you have old feature memory markdown files:

```bash
rails fm:migrate
```

This will create new IDM classes for each old feature memory file. You'll need to manually review and update the generated classes.

## Feature Types

The IDM system supports all types of features:

### 1. Service Features
```ruby
class FeatureMemories::EmailVerificationService < ApplicationFeatureMemory
  feature_spec do
    requirements do
      feature_type :service
      input_fields emails: "Array of email addresses"
      output "Verification status for each email"
      queue_system :sidekiq
    end
  end
end
```

### 2. UI Features
```ruby
class FeatureMemories::DarkModeToggle < ApplicationFeatureMemory
  feature_spec do
    requirements do
      feature_type :ui
      ui_location :navbar
      user_interaction "Click toggle to switch themes"
      components ["DarkModeToggleComponent", "ThemeProviderComponent"]
      browser_storage "localStorage for theme preference"
    end
  end
end
```

### 3. API Features
```ruby
class FeatureMemories::RestfulUsersApi < ApplicationFeatureMemory
  feature_spec do
    requirements do
      feature_type :api
      endpoints({
        "GET /api/v1/users" => "List users",
        "POST /api/v1/users" => "Create user",
        "PATCH /api/v1/users/:id" => "Update user"
      })
      authentication "Bearer token"
      rate_limiting "100 requests per hour"
    end
  end
end
```

### 4. Model Features
```ruby
class FeatureMemories::UserRolesSystem < ApplicationFeatureMemory
  feature_spec do
    requirements do
      feature_type :model
      models ["User", "Role", "UserRole"]
      associations "User has_many :roles, through: :user_roles"
      validations "Role name must be unique"
      scopes ["User.admins", "User.with_role(:editor)"]
    end
  end
end
```

### 5. Database Migrations
```ruby
class FeatureMemories::AddSoftDeleteToUsers < ApplicationFeatureMemory
  feature_spec do
    requirements do
      feature_type :migration
      tables_affected ["users"]
      columns_added ["deleted_at :datetime", "deleted_by_id :integer"]
      indexes ["deleted_at", "deleted_by_id"]
      rollback_safe true
    end
  end
end
```

### 6. Integration Features
```ruby
class FeatureMemories::StripePaymentIntegration < ApplicationFeatureMemory
  feature_spec do
    requirements do
      feature_type :integration
      external_service "Stripe API v2023-10-16"
      webhooks ["payment.succeeded", "payment.failed"]
      security "Webhook signature verification"
      dependencies ["stripe gem v9.0"]
    end
  end
end
```

## Example: Complete Feature Memory

```ruby
class FeatureMemories::LinkedinDiscoveryInternal < ApplicationFeatureMemory
  FEATURE_ID = "linkedin_discovery_internal"
  
  feature_spec do
    description "Internal LinkedIn Discovery using Puppeteer"
    requested_by "@benjamin"
    created_at "2025-01-06"
    
    requirements do
      input_fields company_id: 291917, 
                   sales_navigator_url: "https://linkedin.com/..."
      output "Person model records"
      queue_system :sidekiq
      ui_location :company_show_page
      dependencies ["ferrum gem", "Redis", "LinkedIn credentials"]
    end
    
    test_data do
      company_id 291917
      company_name "Crowe Norway"
      expected_profiles_count 10..50
    end
  end
  
  implementation_log do
    step "2025-01-06 10:00" do
      action "Created service structure"
      code_ref "app/services/linkedin_discovery_internal_service.rb"
      status :completed
    end
  end
  
  troubleshooting do
    issue "LinkedIn 999 status code" do
      cause "Bot detection triggered"
      solution "Add random delays"
      code_example "sleep(rand(2.0..5.0))"
    end
  end
  
  performance_metrics do
    scraping_time "30-60 seconds per page"
    success_rate "90%"
  end
end
```

## AI Agent Integration

The IDM system is designed to be AI-friendly:

1. **Structured Data**: Easy to parse and update programmatically
2. **Clear Status**: Always know what step the implementation is at
3. **Resume Capability**: Full context available when resuming work
4. **Automatic Tracking**: Can be updated during code generation

## Troubleshooting

### Feature Memory Not Found

Ensure the class name matches the file name:
- File: `app/services/feature_memories/my_feature.rb`
- Class: `FeatureMemories::MyFeature`

### Can't Access in Code

Make sure your service includes the integration module:

```ruby
class MyService < ApplicationService
  # ApplicationService includes FeatureMemoryIntegration
end
```

Or include it manually:

```ruby
class MyController < ApplicationController
  include FeatureMemoryIntegration
end
```