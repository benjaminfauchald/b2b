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

### 4. Troubleshooting
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

# In Ruby code
memory = FeatureMemories::YourFeature
memory.plan_status           # Get plan progress
memory.current_tasks         # Get current tasks
memory.update_task(id, ...) # Update task
memory.log_step(...)        # Log action
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

---

**Remember: IDM is not optional - it's a critical part of our development workflow!**