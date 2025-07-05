# Feature Memory Rules

## Overview
This document defines the rules and guidelines for AI agents to create and maintain feature memory files. Feature memory ensures that if an agent crashes during feature development, a new agent can continue exactly where the previous agent left off with full context.

## When to Create Feature Memory Files

### MANDATORY Creation
Create a feature memory file in `docs/features/` when:
- **Multi-step features**: Any feature requiring 3+ implementation steps
- **Complex features**: Features involving multiple files, components, or systems
- **User requests**: When user explicitly asks for a new feature to be implemented
- **Long-running tasks**: Features expected to take more than 30 minutes
- **Critical features**: Features affecting core functionality or user experience

### OPTIONAL Creation
Consider creating feature memory for:
- **Learning experiments**: Trying new patterns or technologies
- **Refactoring tasks**: Large-scale code reorganization
- **Bug fixes**: Complex bugs requiring multiple investigation steps

### DO NOT Create
Skip feature memory for:
- **Simple tasks**: Single-file edits or trivial changes
- **Documentation updates**: Simple documentation changes
- **Quick fixes**: 1-2 line code changes
- **Immediate tasks**: Tasks completed in single session

## File Naming Convention

### Format
`[feature_name_in_snake_case].md`

### Examples
- `user_authentication_system.md`
- `csv_import_optimization.md`
- `email_verification_feature.md`
- `linkedin_profile_integration.md`

### Rules
- Use descriptive, specific names
- Use snake_case formatting
- Avoid abbreviations unless standard (e.g., `api`, `ui`, `csv`)
- Include version numbers if applicable (e.g., `api_v2_migration.md`)

## Feature Memory Lifecycle

### 1. Feature Planning Phase
```markdown
Status: planning
- Create initial feature memory file
- Define requirements and architecture
- Document technical decisions
- Set up implementation plan
```

### 2. Development Phase
```markdown
Status: in_progress
- Update progress after each major step
- Document code references as you create them
- Record technical decisions and rationale
- Update conversation context
```

### 3. Testing Phase
```markdown
Status: in_progress
- Document test results
- Record any issues discovered
- Update implementation based on test feedback
```

### 4. Completion Phase
```markdown
Status: completed
- Final progress update
- Document lessons learned
- Archive or move to completed section
```

### 5. Failure/Pause Phase
```markdown
Status: failed|paused
- Document what went wrong
- Record blockers and issues
- Provide clear next steps for recovery
```

## Required Sections

### Essential Information
- **Feature Information**: Name, status, dates, agent session
- **Overview**: Clear description of feature purpose
- **Requirements**: Detailed checklist of what needs to be done
- **Technical Plan**: Architecture and implementation steps
- **Current Progress**: Exact current state and next actions

### Context Preservation
- **Technical Decisions**: Why certain choices were made
- **Code References**: Links to relevant code with line numbers
- **Conversation Context**: Key discussions and decisions
- **Blockers & Issues**: Current problems and resolution attempts

### Recovery Information
- **Next Action**: Specific next step for continuing agent
- **Dependencies**: What needs to be completed first
- **Test Status**: Current testing state
- **Environment**: Any special setup or configuration

## Update Frequency

### When to Update
- **Before major steps**: Update plan before starting significant work
- **After completion**: Update progress after completing steps
- **During blockers**: Document issues immediately when encountered
- **Before breaks**: Update before ending work session
- **After decisions**: Record technical decisions immediately

### What to Update
- Current progress and next actions
- Technical decisions made
- Code references created or modified
- Test results and validation
- Conversation context and key discussions

## Integration with Development Workflow

### Git Integration
- Commit feature memory files with related code changes
- Include memory file updates in pull requests
- Use memory files for commit message context

### Testing Integration
- Update test status in memory files
- Document test failures and resolutions
- Record test coverage and validation results

### Code Review Integration
- Include memory files in code review process
- Use memory files to explain complex decisions
- Update memory files based on review feedback

## Best Practices

### Writing Guidelines
- **Be specific**: Use exact file names, line numbers, and code references
- **Be comprehensive**: Include all context a new agent would need
- **Be current**: Keep information up-to-date and accurate
- **Be clear**: Use simple, direct language

### Context Preservation
- **Full conversation history**: Include all relevant discussions
- **Decision rationale**: Explain why choices were made
- **Alternative options**: Record what was considered but not chosen
- **Future considerations**: Note potential future improvements

### Recovery Optimization
- **Clear next steps**: Provide specific actions for continuing agent
- **Dependencies**: List what must be completed first
- **Environment setup**: Document any special requirements
- **Testing state**: Clearly indicate what has been tested

## Example Workflow

### Starting a Feature
1. Create feature memory file from template
2. Fill in basic information and requirements
3. Document initial technical plan
4. Begin implementation with regular updates

### Continuing a Feature
1. Read existing feature memory file
2. Understand current progress and context
3. Review technical decisions and rationale
4. Continue from documented next action
5. Update memory file with progress

### Completing a Feature
1. Update final progress and status
2. Document lessons learned
3. Record any future considerations
4. Mark as completed with final notes

## Quality Assurance

### Before Committing
- [ ] Feature memory file exists for significant features
- [ ] All required sections are complete
- [ ] Current progress accurately reflects actual state
- [ ] Next actions are clear and specific
- [ ] Code references are accurate and up-to-date

### During Code Review
- [ ] Memory file updated with implementation changes
- [ ] Technical decisions documented with rationale
- [ ] Test results and validation recorded
- [ ] Conversation context preserved

### After Completion
- [ ] Final status update completed
- [ ] Lessons learned documented
- [ ] Future considerations noted
- [ ] File marked as completed or archived

## Templates and Examples

### Quick Start
1. Copy `docs/features/templates/feature_template.md`
2. Rename to your feature name
3. Fill in feature information section
4. Begin documenting your implementation

### Reference Examples
- `docs/features/feature_memory_system.md` - This implementation
- `docs/features/templates/feature_template.md` - Empty template

## Emergency Recovery

### If Agent Crashes
1. Look for feature memory file in `docs/features/`
2. Read full context and current progress
3. Review technical decisions and rationale
4. Continue from documented next action
5. Update memory file with recovery notes

### If Memory File Missing
1. Search git history for related commits
2. Review recent code changes
3. Check existing documentation
4. Create new memory file from current state
5. Document what was recovered vs. lost

## Automation Opportunities

### Future Enhancements
- Automated memory file creation from commit messages
- Integration with CI/CD pipeline for progress tracking
- Automated context preservation from conversation logs
- Template validation and completeness checking
- Progress visualization and reporting tools