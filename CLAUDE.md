# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

### Enhanced Deployment Scripts with Quality Checks
**ALWAYS use these scripts for deployment - they ensure code quality and test reliability:**

#### Simple Deploy (Quick Push to Master)
```bash
./bin/simple_deploy [commit_message]
```
- **Use when**: You're already on master branch and want to deploy current changes
- **Automatic Quality Checks**:
  - ✅ Runs `bundle exec rubocop --autocorrect` and commits any style fixes
  - ✅ Runs critical domain CSV import tests (MANDATORY - deployment aborts if failing)
  - ✅ Attempts to run full test suite (optional - continues if fails/times out)
  - ✅ Commits changes and pushes to master

#### Full Versioned Deploy (Develop → Master)
```bash
./bin/deploy [patch|minor|major] "Release message"
```
- **Use when**: Deploying from develop branch with version bumping
- **Workflow**: develop → master → tag → push
- **Same quality checks as simple deploy plus version management**
- **Release Name Format**: Automatically creates "Release X.Y.Z: [message]" format
- **Examples**:
  - `./bin/deploy patch "Fix user authentication bug"` → Creates "Release 1.2.1: Fix user authentication bug"
  - `./bin/deploy minor "Add new CSV import features"` → Creates "Release 1.3.0: Add new CSV import features"  
  - `./bin/deploy major "Major UI overhaul"` → Creates "Release 2.0.0: Major UI overhaul"

#### Legacy Manual Deployment (DEPRECATED)
❌ **DO NOT USE**: Manual git commands without quality checks
❌ **AVOID**: `git push origin master` without running tests
❌ **AVOID**: Committing without RuboCop checks

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

## Guard + Claude Integration
- Guard is set up to automatically run tests and generate failure reports
- When tests fail, check `tmp/test_failures.md` for detailed failure information
- Use `./bin/claude-guard prompt` to get a formatted prompt for Claude to fix failures
- Use `./bin/claude-guard watch` to automatically detect new failures and generate prompts
- **Workflow**: Start Guard → Make changes → Guard detects failures → Copy generated prompt to Claude → Claude fixes tests → Guard auto-reruns

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