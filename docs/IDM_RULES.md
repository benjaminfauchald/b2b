# IDM (Integrated Development Memory) Rules & Guidelines

## 🎯 Purpose
IDM is a mandatory system for tracking all feature development in this codebase. It ensures continuity between AI agents, maintains development history, and provides a single source of truth for feature implementation.

## 🔍 Discovery Methods

### 1. IDM Indicators in Code Files
All files related to an IDM-tracked feature include clear header comments:
```ruby
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/linkedin_discovery_internal.rb
#
# IMPORTANT: When making changes to this service:
# 1. Check IDM status: FeatureMemories::LinkedinDiscoveryInternal.plan_status
# 2. Update implementation_log with your changes
# 3. Follow the IDM communication protocol in CLAUDE.md
# ============================================================================
```

### 2. IDM Discovery Rake Tasks
Use these commands to find and work with IDM:
- `rails idm:find[keyword]` - Search for IDM files
- `rails idm:status[feature_id]` - Check feature status
- `rails idm:list` - List all IDM features
- `rails idm:instructions` - Show IDM workflow

### 3. IDM File Location
All IDM files are stored in: `app/services/feature_memories/`

## 📋 MANDATORY Workflow for ALL Features

### Before Starting ANY Work:
1. **Check for existing IDM:**
   ```bash
   rails idm:find[feature_name]
   ```

2. **If no IDM exists, create one:**
   ```bash
   rails generate feature_memory feature_name "Description"
   ```

3. **Check current status:**
   ```ruby
   memory = FeatureMemories::YourFeature
   puts memory.plan_status
   ```

### During Development:

#### Show Plan Progress (BEFORE making changes):
```
📋 IDM Plan Status for [Feature Name]:
Progress: X% Complete (Y/Z tasks)
Current Task: [Task description]
Status: [in_progress/pending]
```

#### Update Task Status:
```ruby
memory.update_task(task_id, status: :in_progress)
```

#### Log Every Major Action:
```ruby
memory.log_step("What you did",
                decision: "Why you did it this way",
                code_ref: "file.rb:42",
                status: :completed)
```

#### Show Updates (AFTER changes):
```
📝 IDM Log Updated:
- Action: [What was done]
- Decision: [Why it was done this way]
- Code Ref: [file:line]
- Next: [What comes next]
```

## 🚨 Critical Rules

### RULE 1: Always Update IDM
**EVERY code change MUST be logged in the IDM implementation_log**

Bad:
```ruby
# Make changes without updating IDM
```

Good:
```ruby
# Make changes
memory.log_step("Added validation", 
                decision: "Used Rails validators",
                code_ref: "app/models/user.rb:42")
```

### RULE 2: Show Progress to Users
**Users must see IDM status with every response**

Bad:
```
I'll add that validation for you.
[makes changes]
Done!
```

Good:
```
📋 IDM Plan Status for Email Validation:
Progress: 25% Complete (2/8 tasks)
Current Task: Add validation rules

I'll add the email validation now...
[makes changes]

📝 IDM Log Updated:
- Action: Added email format validation
- Decision: Used Rails built-in validators
- Code Ref: app/models/user.rb:42
- Next: Write validation tests
```

### RULE 3: Follow the Plan
**Work according to the implementation_plan in IDM**

- Check plan before starting: `memory.current_tasks`
- Update task status when starting/completing
- Don't skip ahead without updating previous tasks

### RULE 4: Document Decisions
**Every technical decision must be documented**

Include:
- What you did (`action`)
- Why you chose this approach (`decision`)
- Any challenges encountered (`challenge`)
- How you solved them (`solution`)
- Where the code lives (`code_ref`)

### RULE 5: UI Testing is Mandatory
**Every feature MUST have comprehensive UI testing before completion**

Requirements:
- **Test Coverage**: Minimum 90% coverage of UI functionality
- **Happy Path Tests**: Core user journeys must work perfectly
- **Edge Case Tests**: Boundary conditions and unusual inputs
- **Error State Tests**: Graceful error handling and user feedback
- **Accessibility Tests**: WCAG compliance and keyboard navigation
- **Performance Tests**: Load times and responsiveness validation

UI Testing Status:
```bash
rails idm:ui_status[feature_id]        # Check UI test status
rails idm:completion_status[feature_id] # Full completion check
rails idm:update_ui_test[feature_id,scenario_id,status] # Update test status
```

**MANDATORY Before Feature Completion:**
- All critical UI tests must pass
- Test coverage must meet minimum requirement (90%)
- No failing UI tests
- Accessibility requirements verified
- Performance thresholds met

## 📝 IDM Structure

Each IDM file contains:

### 1. Feature Specification
```ruby
feature_spec do
  description "What this feature does"
  requested_by "@username"
  created_at "YYYY-MM-DD"
  
  requirements do
    feature_type :service/:ui/:api
    input_fields {...}
    output "What it produces"
    dependencies [...]
  end
end
```

### 2. Implementation Plan
```ruby
implementation_plan do
  task "Task description" do
    priority :high/:medium/:low
    estimated_time "X hours"
    status :pending/:in_progress/:completed
    tags :backend, :frontend, etc
  end
end
```

### 3. Implementation Log
```ruby
implementation_log do
  step "timestamp" do
    action "What was done"
    decision "Why this way"
    challenge "What was difficult"
    solution "How it was solved"
    code_ref "file:line"
    status :completed/:in_progress
  end
end
```

### 4. UI Testing (MANDATORY)
```ruby
ui_testing do
  test_coverage_requirement 90
  mandatory_before_completion true
  test_frameworks :rspec, :capybara, :puppeteer
  
  happy_path "User can successfully submit form" do
    test_type :system
    user_actions ["navigate_to_form", "fill_required_fields", "submit_form"]
    expected_outcome "Form submitted successfully with confirmation message"
    components_under_test ["FormComponent", "SubmitButtonComponent"]
    priority :critical
  end
  
  edge_case "Handles empty form submission" do
    test_type :system
    user_actions ["navigate_to_form", "submit_empty_form"]
    expected_outcome "Validation errors displayed appropriately"
    priority :high
  end
  
  accessibility "Keyboard navigation works throughout feature" do
    test_type :system
    accessibility_requirements ["tab_navigation", "enter_submit", "aria_labels", "focus_management"]
    priority :high
  end
end
```

### 5. Troubleshooting
```ruby
troubleshooting do
  issue "Problem description" do
    cause "Why it happened"
    solution "How to fix"
    prevention "How to avoid"
  end
end
```

## 🔄 Cross-Agent Continuity

### When Starting Work:
1. Always check for CLAUDE.md and read it
2. Run `rails idm:find[feature]` to find related work
3. Read the full IDM file before making changes
4. Continue from where the last agent left off

### When Ending Work:
1. Update IDM with all changes made
2. Set current task status appropriately
3. Document any blockers or next steps
4. Ensure IDM reflects current state

## 🎓 Examples

### Example 1: Starting Feature Work
```ruby
# 1. Find IDM
$ rails idm:find[payment]
# Found: app/services/feature_memories/payment_integration.rb

# 2. Check status
$ rails idm:status[payment_integration]
# Progress: 40% Complete (4/10 tasks)
# Current Task: Implement Stripe webhook handling

# 3. Show user the plan
"📋 IDM Plan Status for Payment Integration:
Progress: 40% Complete (4/10 tasks)
Current Task: Implement Stripe webhook handling
Status: pending

I'll start implementing the Stripe webhook handling..."
```

### Example 2: Debugging Existing Feature
```ruby
# 1. Find feature being debugged
$ rails idm:find[linkedin]

# 2. Add debugging entry to IDM
memory = FeatureMemories::LinkedinDiscoveryInternal
memory.log_step("Debugging CSRF token issue",
                challenge: "Form submission failing silently",
                solution: "Added authenticity_token to form",
                code_ref: "app/components/linkedin_component.rb:45",
                status: :completed)

# 3. Update troubleshooting section
memory.troubleshooting do
  issue "CSRF token validation failure" do
    cause "Form missing authenticity_token"
    solution "Add token to form with form_authenticity_token helper"
    prevention "Always use Rails form helpers for CSRF protection"
  end
end
```

### Example 3: Adding UI Testing to Feature
```ruby
# 1. Add comprehensive UI testing to feature memory
memory = FeatureMemories::PaymentIntegration
memory.ui_testing do
  test_coverage_requirement 95
  mandatory_before_completion true
  test_frameworks :rspec, :capybara, :puppeteer
  
  happy_path "User completes successful payment" do
    test_type :system
    user_actions ["select_payment_method", "enter_card_details", "submit_payment"]
    expected_outcome "Payment processed and confirmation displayed"
    components_under_test ["PaymentFormComponent", "CardInputComponent"]
    test_file "spec/system/payment_flow_spec.rb"
    priority :critical
    estimated_time "45 minutes"
  end
  
  edge_case "Handles payment failure gracefully" do
    test_type :system
    user_actions ["enter_invalid_card", "submit_payment"]
    expected_outcome "Error message displayed, form remains accessible"
    priority :high
    test_data { card_number: "4000000000000002" } # Declined card
  end
  
  accessibility "Payment form is fully accessible" do
    test_type :system
    accessibility_requirements ["keyboard_navigation", "screen_reader_support", "error_announcements"]
    priority :high
  end
end

# 2. Check UI testing status
$ rails idm:ui_status[payment_integration]

# 3. Update test status as tests are written and executed
$ rails idm:update_ui_test[payment_integration,scenario_id,passed]

# 4. Final completion check
$ rails idm:completion_status[payment_integration]
```

## 🚀 Quick Reference

```bash
# Find features
rails idm:find[keyword]

# Check status  
rails idm:status[feature_id]

# List all features
rails idm:list

# See instructions
rails idm:instructions

# UI Testing Commands
rails idm:ui_status[feature_id]              # Check UI test status
rails idm:completion_status[feature_id]      # Full completion check
rails idm:update_ui_test[feature_id,scenario_id,status] # Update test

# In Ruby code
memory = FeatureMemories::YourFeature
memory.plan_status           # Get plan progress
memory.current_tasks         # Get current tasks
memory.update_task(id, ...) # Update task
memory.log_step(...)        # Log action
memory.ui_testing_status     # Get UI test status
memory.ready_for_completion? # Check if ready
memory.completion_blockers   # Get blocking issues
```

## ❓ FAQ

**Q: Do I need to update IDM for small bug fixes?**
A: Yes, even small changes should be logged. Use a simple log entry.

**Q: What if there's no IDM for the feature I'm working on?**
A: Create one immediately with `rails generate feature_memory`.

**Q: How detailed should log entries be?**
A: Include enough detail that another agent can understand what you did and why.

**Q: What if I'm just reading code?**
A: No IDM update needed for read-only operations.

**Q: Can I modify the implementation plan?**
A: Yes, but document why in the log when you do.

**Q: Is UI testing required for all features?**
A: Yes, unless the feature has no user interface. Backend-only services may skip UI testing but must have comprehensive unit/integration tests.

**Q: What's the minimum UI test coverage required?**
A: 90% by default, but can be configured per feature. Critical user journeys must have 100% coverage.

**Q: Can I complete a feature with failing UI tests?**
A: No, all UI tests must pass before feature completion. Use `rails idm:completion_status[feature_id]` to check blockers.

**Q: What types of UI tests should I write?**
A: Happy path (core functionality), edge cases (boundary conditions), error states (graceful failures), accessibility (WCAG compliance), and performance (load times).

**Q: Which testing frameworks should I use?**
A: RSpec for unit/integration, Capybara/Selenium for system tests, and Puppeteer for complex E2E scenarios. Choose based on the test complexity.

**Q: How do I update UI test status?**
A: Use `rails idm:update_ui_test[feature_id,scenario_id,status]` or update directly in the feature memory file.

---

**Remember: IDM is not optional - it's a critical part of our development workflow!**
**UI Testing is mandatory for feature completion - no exceptions!**