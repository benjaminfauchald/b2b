# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚨 IMPORTANT: Claude Hooks Active

This project uses Claude hooks to enforce IDM (Integrated Development Memory) usage:
- **Pre-edit hook**: Blocks edits to IDM-tracked files until you acknowledge IDM requirements
- **Post-edit hook**: Reminds you to update IDM logs after changes
- **Pre-read hook**: Shows IDM status when reading tracked files

To bypass hooks in emergencies: `export SKIP_IDM=1` (NOT RECOMMENDED)

## 🚀 Quick Start for New AI Agents

When starting work on this codebase:

1. **First, check for existing feature work:**
   ```bash
   rails idm:instructions     # See IDM workflow
   rails idm:list            # List all features with IDM tracking
   rails idm:find[keyword]   # Search for specific features
   ```

2. **Look for IDM indicators in code:**
   - Search for "Feature tracked by IDM:" comments in files
   - These point to the IDM documentation file

3. **Follow the IDM Communication Protocol** (see section below)

4. **Read the complete IDM Rules:**
   - 📚 **MANDATORY**: Read `docs/IDM_RULES.md` for full IDM guidelines
   - This file contains all rules, examples, and workflows

## 🖥️ Browser Testing & Puppeteer Configuration

### MANDATORY: Always Use Large Viewport for Screenshots

**IMPORTANT**: When using MCP Puppeteer tools or browser testing, ALWAYS use these settings for proper full-page screenshots:

#### MCP Puppeteer Navigate
```javascript
mcp__puppeteer__puppeteer_navigate({
  url: "https://example.com",
  launchOptions: {
    headless: false,
    defaultViewport: { width: 1920, height: 1080 },
    args: [
      "--window-size=1920,1080",
      "--start-maximized",
      "--no-sandbox",
      "--disable-setuid-sandbox"
    ]
  }
})
```

#### MCP Puppeteer Screenshot
```javascript
mcp__puppeteer__puppeteer_screenshot({
  name: "screenshot_name",
  width: 1920,
  height: 1080
})
```

#### Standard Puppeteer Tests
All Puppeteer test files should use:
```javascript
const browser = await puppeteer.launch({ 
  headless: false,
  defaultViewport: { width: 1920, height: 1080 },
  args: [
    '--window-size=1920,1080',
    '--start-maximized'
  ]
});
```

### Configuration Files
- **Common Config**: `test/puppeteer/puppeteer_config.js` - Use for consistent settings
- **Claude Settings**: `.claude/settings.json` - Contains toolDefaults for MCP tools
- **Test Files**: Updated to use 1920x1080 viewport automatically

### Why Large Viewport Required
- ❌ **Old (1400x900)**: Incomplete screenshots, missing content below fold
- ✅ **New (1920x1080)**: Full page capture, complete visibility, professional quality

**NEVER use smaller viewport sizes unless specifically requested - screenshots must capture the full page**

### ⚠️ CRITICAL: MCP Tool Parameters Required

Since Claude toolDefaults may not be applied automatically, you MUST manually specify these parameters:

**EVERY TIME you use `mcp__puppeteer__puppeteer_navigate`:**
```javascript
launchOptions: {
  headless: false,
  defaultViewport: { width: 1920, height: 1080 },
  args: ["--window-size=1920,1080", "--start-maximized"]
}
```

**EVERY TIME you use `mcp__puppeteer__puppeteer_screenshot`:**
```javascript
width: 1920,
height: 1080
```

**DO NOT** use these tools without the above parameters - screenshots will be too small and incomplete.

## Quick Reference - Deployment

**One Workflow**: `.github/workflows/main.yml` - Handles all CI/CD needs
**One Deploy Script**: `./bin/deploy` - Smart enough to handle all scenarios

The deploy script is now super simple to use:
- `./bin/deploy` - Quick deploy with patch version
- `./bin/deploy "Fix bug"` - Deploy with message  
- `./bin/deploy minor "New feature"` - Minor version bump
- `./bin/deploy major "Breaking change"` - Major version bump

## Production Server Commands

### Systemd Service Management
- **Service name**: `puma.service` (NOT b2b-rails)
- `sudo systemctl restart puma.service` - Restart Rails/Puma server
- `sudo systemctl status puma.service` - Check service status
- `sudo systemctl stop puma.service` - Stop the service
- `sudo systemctl start puma.service` - Start the service
- `sudo journalctl -u puma.service -f` - View real-time logs
- `sudo journalctl -u puma.service -n 100` - View last 100 log lines

### SSH Access
- **Production server**: `app.connectica.no`
- **SSH user**: `benjamin`
- **App directory**: `~/b2b`
- **Environment file**: `~/b2b/.env.production`

Example commands:
```bash
# SSH into production
ssh benjamin@app.connectica.no

# Restart Rails after config changes
ssh benjamin@app.connectica.no "sudo systemctl restart puma.service"

# Upload environment file
scp .env.production benjamin@app.connectica.no:~/b2b/

# Check logs
ssh benjamin@app.connectica.no "sudo journalctl -u puma.service -n 50"
```

## Development Commands

### Rails Server & Development Stack
- `./bin/rake dev` - **RECOMMENDED** Start full development stack (Rails + ngrok tunnel)
- `./bin/rake dev:stop` - Stop all development services
- `./bin/rake dev:status` - Check status of development services
- `./bin/rake restart` - Restart only Rails server (kills old processes and starts fresh)
- `./bin/rake kill` - Kill any Rails server running on port 3000
- `./bin/rails console` - Open Rails console
- **IMPORTANT**: Rails server ALWAYS starts on port 3000 and binds to 0.0.0.0
- `rake test:restart` - Restart Rails server for testing purposes
- **BEST PRACTICE**: Use `bundle exec rake test:restart` instead of Bash(PORT=3000 rails server &) or any other starting of rails

## API Notes

### Brreg Financial Data API
- The API returns 404 if no financial data is found for a company, which is a feature not an error
- Example working company URL with financial info: https://data.brreg.no/regnskapsregisteret/regnskap/989164155
- Example company URL without financial info (returns 404): https://data.brreg.no/regnskapsregisteret/regnskap/932968126
- The api.brreg.no API gives 404 if there is not found any financial data. It's not an error, it's a feature

## Deployment & Quality Control

### Unified Deploy Script with Quality Checks
**ALWAYS use this script for deployment - it ensures code quality and test reliability:**

#### Smart Deploy (Auto-detects branch and mode)
```bash
./bin/deploy                              # Deploy with default message
./bin/deploy "Commit message"             # Deploy with custom message
./bin/deploy patch "Release message"      # Patch version bump (1.2.3 → 1.2.4)
./bin/deploy minor "Release message"      # Minor version bump (1.2.3 → 1.3.0)
./bin/deploy major "Release message"      # Major version bump (1.2.3 → 2.0.0)
```

**How it works**:
- **From master branch**: Simple mode - pushes directly and creates tag
- **From develop branch**: Full mode - merges to master, then creates tag
- **Automatic Quality Checks**:
  - ✅ Runs `bundle exec rubocop --autocorrect` and commits any style fixes
  - ✅ Runs critical domain CSV import tests (MANDATORY - deployment aborts if failing)
  - ✅ Attempts to run full test suite (optional - continues if fails/times out)
  - ✅ Creates version tag and pushes to trigger GitHub Actions deployment

**Examples**:
- `./bin/deploy` → Creates patch release with default message
- `./bin/deploy "Fix authentication bug"` → Creates patch release with message
- `./bin/deploy minor "Add CSV import"` → Creates minor release v1.3.0
- `./bin/deploy major "API v2"` → Creates major release v2.0.0

#### Manual Deployment (NEVER USE)
❌ **DO NOT USE**: Manual git commands without quality checks
❌ **AVOID**: `git push origin master` without running tests
❌ **AVOID**: Creating tags manually without the deploy script

### Release Naming Convention
**Automatic Release Naming**: The deploy script automatically creates properly formatted release names:
- **Format**: `Release X.Y.Z: [descriptive message]`
- **Examples**:
  - `Release 1.2.1: Fix deployment script for production server environment`
  - `Release 1.3.0: Add domain CSV import functionality with error handling`
  - `Release 2.0.0: Major database schema migration and API restructure`

**Message Guidelines**:
- Use descriptive, professional language
- Focus on the main feature/fix being deployed
- Keep under 80 characters for readability
- Start with action verb (Fix, Add, Update, Remove, etc.)

### Quality Control Requirements
**MANDATORY for all deployments:**
1. **RuboCop Style Compliance**: All code must pass `bundle exec rubocop`
2. **Critical Test Verification**: Domain CSV import tests must pass (23 tests)
3. **Code Standards**: Follow existing patterns and conventions
4. **No Breaking Changes**: Existing functionality must remain intact
5. **Proper Release Naming**: Use descriptive messages for version tags

### Deployment Failure Handling
- **RuboCop Failures**: Script auto-fixes correctable issues, manual fixes required for others
- **Critical Test Failures**: Deployment immediately aborts - fix tests before retry
- **Full Test Suite Failures**: Deployment continues (critical tests already passed)
- **Network Issues**: Retry deployment after connectivity restored

## Development Best Practices
- Never use localhost for any server setup or testing use local.connectica.no
- Always touch a file before you write to avoid this error "Error: File has not been read yet. Read it first before writing to it."
- Make sure we dont start to make duplicates of files like homepage_hero_component 2.rb or /homepage_stats_component 2.r. We ALWAYS need to work on the actual file or the system will lose integrity!
- Make sure that we write any temporary files and scripts to the tmp/ folder
- **ALWAYS use enhanced deployment scripts** - never push manually without quality checks

## Rails 8 + ViewComponent Compatibility (CRITICAL)
**SOLVED**: This application uses a comprehensive ViewComponent Rails 8 compatibility solution.

### Full Documentation
📚 **See `docs/VIEWCOMPONENT_RAILS8_COMPATIBILITY.md` for complete details on:**
- The core problem and solution architecture
- CI/CD test requirements and common issues
- Debugging and monitoring procedures
- Quick checklist for new components

### Key Files & Configuration:
- `config/initializers/viewcomponent_rails8_compatibility.rb` - Core Rails 8 compatibility patch
- `config/application.rb` - Manual autoload_paths configuration BEFORE freezing
- `config/environments/production.rb` - Production-specific ViewComponent settings
- `lib/tasks/viewcomponent_rails8.rake` - Verification and precompilation tasks
- `config/boot.rb` - CI environment Array monkey patch

### CI Test Requirements:
**IMPORTANT**: All ViewComponent instantiations in CI must include required parameters:
```ruby
# ❌ WRONG - Will fail CI tests
ButtonComponent.new

# ✅ CORRECT - Include all required parameters
ButtonComponent.new(text: 'Test Button')
```

### Testing Status:
- ✅ All 183 ViewComponent specs pass (0 failures, 1 pending)
- ✅ No FrozenError in development or production
- ✅ Compatible with Rails 8 + Propshaft asset pipeline
- ✅ Proper Zeitwerk autoloading integration

**DO NOT MODIFY** these ViewComponent compatibility files without understanding the Rails 8 autoload_paths freezing behavior.

## Test Management Rules - CRITICAL ⚠️
**MANDATORY WORKFLOW for ANY code changes:**

1. **Before Making Changes**: 
   - Search for existing tests related to the files/functionality you're about to modify
   - Use `grep -r "YourClassName" spec/` or `./bin/claude-guard status` to find relevant tests
   - Check test coverage for controllers, models, services, components, etc.

2. **During Development**:
   - Run relevant tests BEFORE making changes to establish baseline: `bundle exec rspec spec/path/to/relevant_spec.rb`
   - Make your code changes
   - Run the same tests again to check for breakage

3. **Test Breakage Protocol**:
   - **NEVER** write code that breaks existing tests without explicit user approval
   - If tests will break due to intentional changes:
     a. **STOP** and inform the user about which tests will break and why
     b. Explain what the test changes would need to be
     c. Wait for user confirmation before proceeding
     d. Only proceed after user explicitly approves the test modifications

4. **After Changes**:
   - Run full test suite or use Guard to detect all breakages
   - Fix any unintentional test failures immediately
   - Update tests that were approved for modification by the user

5. **Test Documentation**:
   - When updating tests, explain why the change was necessary
   - Ensure test descriptions still accurately reflect the expected behavior
   - Maintain or improve test coverage

**Example Test Check Commands:**
```bash
# Check for tests related to a specific file
grep -r "CompaniesController" spec/
grep -r "Person" spec/models/
grep -r "authentication" spec/

# Run specific test files
bundle exec rspec spec/controllers/companies_controller_spec.rb
bundle exec rspec spec/models/person_spec.rb

# Check test status
./bin/claude-guard status
```

## Rails 8 + CI/CD Testing Rules - CRITICAL ⚠️
**MANDATORY checks before deployment to prevent CI/CD failures:**

### Pre-Deployment Testing Checklist
1. **CI Environment Test**: `CI=true bundle exec rspec spec/components/button_component_spec.rb --dry-run`
2. **Critical Domain Tests**: `CI=true bundle exec rspec spec/models/domain_import_result_spec.rb`
3. **ViewComponent Loading**: `CI=true bundle exec rspec spec/components/ --dry-run | head -10`
4. **Controller Specs**: Test at least one controller spec with CI flag

### Rails 8 Compatibility Rules
**NEVER modify these files without testing CI compatibility:**
- `config/boot.rb` - Contains Rails 8 autoload_paths freeze protection
- `config/application.rb` - Early autoload path configuration
- `config/initializers/viewcomponent_rails8_compatibility.rb` - Frozen array handling
- `lib/guard/rspec_formatter.rb` - CI-specific Guard formatter

### FrozenError Prevention
**Root Cause**: Rails 8 freezes `autoload_paths` early in CI environments with eager loading
**Symptoms**: `FrozenError: can't modify frozen Array` in CI/CD pipeline
**Test Command**: `CI=true bundle exec rspec --dry-run` should load without errors

### Component Development Rules
1. **Always test components with CI flag**: `CI=true bundle exec rspec spec/components/your_component_spec.rb`
2. **Check autoload path modifications**: New engines/gems that modify autoload_paths need CI testing
3. **Eager loading validation**: If adding new autoload paths, test with `config.eager_load = true`

### Deployment Gate Commands
**BEFORE any deployment, run these commands and ensure they pass:**
```bash
# Core compatibility check
CI=true bundle exec rspec spec/models/domain_import_result_spec.rb

# ViewComponent compatibility
CI=true bundle exec rspec spec/components/button_component_spec.rb --dry-run

# System initialization test
CI=true bundle exec rspec spec/controllers/companies_controller_edit_spec.rb --dry-run
```

**If ANY of these fail with FrozenError, deployment MUST be blocked until fixed.**

## Guard + Claude Integration (Enhanced Test Monitoring)
Guard automatically monitors tests and logs failures for easy fixing:

### Quick Commands
- `./bin/claude-guard status` - Check current test status
- `./bin/claude-guard prompt` - Generate Claude prompt for failures (auto-copies to clipboard)
- `./bin/claude-guard watch` - Live monitor test status
- `./bin/test-status` - Quick test status check

### How It Works
1. **Start Guard**: `bundle exec guard` - Monitors file changes and runs tests
2. **Make Changes**: Edit your code
3. **Automatic Logging**: Guard logs all test results to `tmp/guard_logs/`
4. **Check Failures**: Run `./bin/claude-guard status` anytime
5. **Get Fix Prompt**: Run `./bin/claude-guard prompt` to generate and copy Claude prompt
6. **Paste to Claude**: The prompt is auto-copied, just paste here for fixes

### Log Files
- `tmp/guard_logs/current_failures.json` - Current test failures in JSON
- `tmp/guard_logs/failure_summary.md` - Human-readable failure report
- `tmp/guard_logs/failure_history.log` - Historical failure log
- `tmp/test_failures.md` - Legacy failure report (still generated)

### Benefits
- No need to run full test suite manually
- Failures are automatically tracked
- Easy integration with Claude for fixes
- Historical tracking of test failures
- Live monitoring with `watch` command

## Feature Development with Integrated Development Memory (IDM) - MANDATORY

Every feature implementation MUST use the Integrated Development Memory system for documentation and progress tracking. This applies to ALL features:
- Services and background jobs
- UI components and frontend features  
- API endpoints and integrations
- Models and database changes
- Infrastructure and configuration
- Bug fixes and refactoring
- ANY code change that implements functionality

### IDM Communication Requirements - CRITICAL

**For EVERY code change, you MUST show the user:**

1. **BEFORE making changes** - Show current IDM plan status:
   ```
   📋 IDM Plan Status for [Feature Name]:
   Progress: X% Complete (Y/Z tasks)
   Current Task: [Task description]
   Status: [in_progress/pending]
   
   🧪 UI Testing Status:
   Coverage: X% (Y/Z tests passing)
   Status: [passed/incomplete/failed]
   Blockers: [List any UI testing blockers]
   ```

2. **DURING implementation** - Update user on task transitions:
   ```
   ✅ Completed: [Previous task]
   ▶️  Starting: [New task]
   Est. Time: [time estimate]
   
   🧪 UI Testing Update:
   Added: [New test scenarios]
   Status: [Current test execution status]
   ```

3. **AFTER changes** - Show what was logged to IDM:
   ```
   📝 IDM Log Updated:
   - Action: [What was done]
   - Decision: [Why it was done this way]
   - Code Ref: [file:line]
   - Test Ref: [test file:line]
   - Next: [What comes next]
   
   🧪 UI Test Status:
   Scenarios Updated: [Number of test scenarios affected]
   Coverage: [Current test coverage percentage]
   ```

**Communication Template for Feature Work:**

When working on ANY feature with an IDM entry, structure your responses like this:

1. Start with IDM status check
2. Explain what you're about to do
3. Make the changes
4. Show IDM updates
5. Preview what comes next

This keeps the user informed about:
- Where we are in the plan
- Why decisions are being made
- What was implemented
- What's coming next

### Example IDM Communication Pattern

```
User: Add validation to the email field

Assistant:
📋 IDM Plan Status for Email Validation:
Progress: 25% Complete (2/8 tasks)
Current Task: Research existing validation patterns
Status: in_progress

I'll search for existing email validation patterns in the codebase...

[Makes code changes]

✅ Completed: Research existing validation patterns
▶️  Starting: Add email format validation to User model
Est. Time: 15 minutes

[Implements validation]

📝 IDM Log Updated:
- Action: Added email format validation using built-in Rails validators
- Decision: Used validates :email, format: { with: URI::MailTo::EMAIL_REGEXP } for RFC compliance
- Code Ref: app/models/user.rb:42
- Next: Write RSpec tests for email validation
```

### Feature Command Workflow

When the user uses the `/feature` command OR requests ANY new functionality, follow these steps:

1. **Generate Feature Memory** - Create IDM entry with initial requirements (`rails generate feature_memory <name>`)
2. **Git commit** - Commit current changes to separate from new feature work
3. **Understand the problem** - Analyze the feature request and requirements
4. **Search the codebase** - Find relevant files and existing patterns
5. **Check for useful gems** - Research libraries that could help implementation
6. **Use context7 MCP** - Look up documentation for any frameworks or libraries
7. **Follow guidelines**:
   - SCT Service Control Table patterns
   - ViewComponent, Tailwind, and Flowbite best practices
8. **Create implementation plan** in IDM:
   - Add tasks to implementation_plan block
   - Set priorities and time estimates
   - Define clear task descriptions
9. **Show plan to user** - Display IDM plan status before starting
10. **Await user acceptance** - Get approval before starting implementation
11. **Update IDM continuously**:
    - Show task transitions to user
    - Update implementation_log at each major step
    - Document decisions, challenges, and solutions
    - Link to code and test references
12. **Implement the feature** - Write code following the plan
13. **Add UI Testing Requirements** - Create comprehensive UI test scenarios:
    - Happy path tests for core functionality
    - Edge case tests for boundary conditions
    - Error state tests for graceful failure handling
    - Accessibility tests for WCAG compliance
    - Performance tests for load times and responsiveness
14. **Write and Execute Tests** - Create comprehensive tests for the implementation:
    - Unit tests for components and services
    - Integration tests for API endpoints
    - System tests for user workflows
    - Execute UI tests and update status in IDM
15. **Verify Completion Requirements**:
    - Check `rails idm:completion_status[feature_id]`
    - Ensure 90%+ UI test coverage
    - All critical tests must pass
    - No completion blockers remaining
16. **Review quality** - Must score 7/10 or higher, iterate if needed
17. **Complete IDM documentation** - Final implementation details, lessons learned
18. **Create descriptive commit** and **Push with PR**

### IDM Quick Reference

```bash
# Generate new feature memory
rails generate feature_memory feature_name "Description"

# Check status
rails feature_memory:status feature_name

# Export to markdown
rails feature_memory:export feature_name

# Resume work
rails feature_memory:resume feature_name

# UI Testing Commands
rails idm:ui_status[feature_id]                    # Check UI test status
rails idm:completion_status[feature_id]            # Full completion check
rails idm:update_ui_test[feature_id,scenario_id,status] # Update test status
```

### Accessing IDM in Your Responses

**Always check and show IDM status before working on a feature:**

```ruby
# Get the feature memory
memory = ApplicationFeatureMemory.find('feature_name')
# OR for specific features:
memory = FeatureMemories::LinkedinDiscoveryInternal

# Check plan status
status = memory.plan_status
# => { total: 8, pending: 2, in_progress: 1, completed: 5, completion_percentage: 62.5 }

# Get current task
current = memory.current_tasks.first
# => { description: "Write tests", status: :in_progress, priority: :high }

# Update task when starting work
memory.update_task(task_id, status: :in_progress)

# Log decisions and progress
memory.log_step("Added validation", 
                decision: "Used Rails built-in validators for simplicity",
                code_ref: "app/models/user.rb:42",
                status: :completed)
```

### Required IDM Components

Every feature must document:
- Requirements and test data
- Implementation progress with timestamps
- Code and test references
- Challenges and solutions
- Performance metrics
- Troubleshooting guides

See `docs/INTEGRATED_DEVELOPMENT_MEMORY.md` for full IDM documentation.

## Git Commit Guidelines
- When creating commits, DO NOT include the "Generated with Claude Code" or "Co-Authored-By: Claude" lines
- Keep commit messages focused on the technical changes only
- Use detailed, elaborate commit messages with the following structure:
  - Start with a concise summary line (50-72 characters)
  - Follow with a blank line
  - Include a detailed bullet list of all specific changes made
  - Explain the reasoning behind the changes and what problems they solve
  - Mention any UI/UX improvements or design system updates
  - Note any temporary changes, workarounds, or future considerations
  - End with a brief summary paragraph of what was accomplished
  - Example format:
    ```
    Improve authentication pages design and UX consistency

    - Remove duplicate OAuth buttons and "Forgot password" links from shared links partial
    - Update sign-in and create account buttons to use Flowbite primary button styling
    - Standardize dividers with uppercase text and flexbox layout  
    - Add support for custom OAuth button text (e.g., "Create account with" vs "Sign in with")
    - Ensure consistent button styling: rounded-lg, px-5 py-2.5, focus:ring-4
    - Comment out Google OAuth (keeping code for future implementation)
    - Fix dark mode color inconsistencies across all authentication components

    All the requested design improvements have been implemented to ensure consistency
    across the authentication flow and align with the Flowbite design system used
    throughout the application.
    ```