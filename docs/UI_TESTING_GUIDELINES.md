# UI Testing Guidelines for IDM Feature Development

## 🎯 Overview

This document provides comprehensive guidelines for implementing UI testing as part of the IDM (Integrated Development Memory) system. Every feature developed through IDM must include thorough UI testing to ensure proper functionality, accessibility, and user experience.

## 🚨 Mandatory Requirements

### Test Coverage Requirements
- **Minimum Coverage**: 90% of UI functionality must be tested
- **Critical Path Coverage**: 100% coverage for critical user journeys
- **Error State Coverage**: All error conditions must have corresponding tests
- **Accessibility Coverage**: WCAG 2.1 AA compliance verification

### Test Types Required
1. **Happy Path Tests**: Core functionality works as expected
2. **Edge Case Tests**: Boundary conditions and unusual inputs
3. **Error State Tests**: Graceful error handling and recovery
4. **Accessibility Tests**: Keyboard navigation, screen readers, ARIA
5. **Performance Tests**: Load times, interaction responsiveness
6. **Integration Tests**: API endpoints and data flow

## 📋 Test Categories

### 1. Happy Path Tests
**Purpose**: Verify core functionality works as intended

**Requirements**:
- Test the primary user journey from start to completion
- Verify all expected outcomes and state changes
- Include positive user feedback (success messages, confirmations)
- Test with realistic data scenarios

**Example**:
```ruby
happy_path "User can successfully submit contact form" do
  test_type :system
  user_actions [
    "navigate_to_contact_page",
    "fill_required_fields",
    "submit_form"
  ]
  expected_outcome "Form submitted with success message and email sent"
  components_under_test ["ContactFormComponent", "SubmitButtonComponent"]
  priority :critical
  estimated_time "30 minutes"
end
```

### 2. Edge Case Tests
**Purpose**: Ensure system handles boundary conditions gracefully

**Requirements**:
- Test minimum and maximum input values
- Test empty/null inputs where applicable
- Test unusual but valid data combinations
- Verify system remains stable under edge conditions

**Example**:
```ruby
edge_case "Handles extremely long text input" do
  test_type :system
  user_actions ["enter_text_exceeding_limit", "attempt_submit"]
  expected_outcome "Character limit enforced with helpful feedback"
  test_data { message: "a" * 5001 } # Exceeds 5000 char limit
  priority :high
end
```

### 3. Error State Tests
**Purpose**: Verify graceful error handling and user feedback

**Requirements**:
- Test all possible error conditions
- Verify appropriate error messages are displayed
- Ensure users can recover from errors
- Test network failures and timeout scenarios

**Example**:
```ruby
error_state "Displays helpful message on server error" do
  test_type :system
  user_actions ["submit_form_during_server_downtime"]
  expected_outcome "User-friendly error message with retry option"
  priority :high
  prerequisites ["mock_server_error"]
end
```

### 4. Accessibility Tests
**Purpose**: Ensure WCAG 2.1 AA compliance and inclusive design

**Requirements**:
- Keyboard navigation throughout the feature
- Screen reader compatibility (ARIA labels, roles, properties)
- Color contrast compliance
- Focus management during dynamic updates
- Error announcements for assistive technologies

**Example**:
```ruby
accessibility "Complete keyboard navigation support" do
  test_type :system
  accessibility_requirements [
    "tab_navigation",
    "enter_submit", 
    "escape_cancel",
    "arrow_selection",
    "focus_management"
  ]
  priority :high
  estimated_time "45 minutes"
end
```

### 5. Performance Tests
**Purpose**: Ensure responsive user experience

**Requirements**:
- Page load times under 3 seconds
- Form submission under 2 seconds
- User interaction response under 1 second
- Large dataset handling efficiency

**Example**:
```ruby
performance "Form submission completes within acceptable time" do
  test_type :system
  performance_thresholds {
    page_load: 3.seconds,
    form_submit: 2.seconds,
    interaction: 1.second
  }
  priority :medium
end
```

### 6. Integration Tests
**Purpose**: Verify end-to-end data flow and API integration

**Requirements**:
- Test API endpoint responses
- Verify data persistence
- Test external service integration
- Validate error handling across system boundaries

## 🛠️ Testing Frameworks

### RSpec + Capybara (System Tests)
**Use for**: User workflow testing, form interactions, page navigation

```ruby
RSpec.describe "User Registration Flow", type: :system do
  it "allows user to create account successfully" do
    visit new_user_registration_path
    
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "SecurePassword123"
    click_button "Create Account"
    
    expect(page).to have_text("Welcome! You have signed up successfully.")
    expect(current_path).to eq(dashboard_path)
  end
end
```

### ViewComponent Tests (Unit)
**Use for**: Component isolation testing, prop validation

```ruby
RSpec.describe ButtonComponent, type: :component do
  it "renders with correct accessibility attributes" do
    component = ButtonComponent.new(text: "Submit", variant: "primary")
    render_inline(component)
    
    expect(rendered_component).to have_css("button[type='submit']")
    expect(rendered_component).to have_css("[aria-label]")
  end
end
```

### Puppeteer (E2E Tests)
**Use for**: Complex user interactions, JavaScript-heavy features, cross-browser testing

```javascript
async function testComplexUserFlow() {
  const page = await createConfiguredPage(browser);
  
  // Navigate and interact
  await page.goto('https://local.connectica.no/feature');
  await page.click('[data-testid="start-process"]');
  await page.waitForSelector('[data-testid="step-2"]');
  
  // Verify state
  const element = await page.$('[data-testid="success-indicator"]');
  expect(element).toBeTruthy();
}
```

## 📝 Test Planning Process

### 1. Analyze Feature Requirements
- Identify all user interactions
- Map user journeys and workflows
- Determine critical vs. non-critical paths
- List external dependencies

### 2. Create Test Scenarios
- Document in IDM ui_testing block
- Assign priority levels (critical, high, medium, low)
- Estimate time requirements
- Define success criteria

### 3. Choose Appropriate Testing Levels
- **Unit**: Individual components
- **Integration**: Component interactions, API calls
- **System**: Complete user workflows
- **E2E**: Cross-browser, complex scenarios

### 4. Implementation Order
1. Start with critical happy path tests
2. Add edge cases for critical functionality
3. Implement error state handling
4. Add accessibility verification
5. Performance validation
6. Integration testing

## 🔍 Test Implementation Guidelines

### Test Structure
```ruby
describe "Feature Name" do
  let(:user) { create(:user) }
  
  before do
    # Setup test conditions
    sign_in user
    setup_test_data
  end
  
  it "descriptive test name focusing on behavior" do
    # Arrange: Set up test conditions
    
    # Act: Perform the action being tested
    
    # Assert: Verify expected outcomes
    expect(page).to have_text("Expected Result")
    
    # Document: Take screenshots for complex flows
    screenshot_and_save_page if complex_feature?
  end
end
```

### Data-Testid Attributes
Use `data-testid` attributes for reliable element selection:

```erb
<%= button_to "Submit", submit_path, 
    data: { testid: "submit-button" },
    class: "btn btn-primary" %>
```

```ruby
# In tests
click_button('[data-testid="submit-button"]')
```

### Test Data Management
- Use FactoryBot for consistent test data
- Create realistic test scenarios
- Include edge case data sets
- Mock external services appropriately

```ruby
# factories/user.rb
FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { "SecurePassword123" }
    
    trait :with_long_name do
      name { "a" * 255 } # Test maximum length
    end
  end
end
```

## 🎨 UI Testing Best Practices

### 1. Test User Behavior, Not Implementation
```ruby
# Good: Tests user behavior
expect(page).to have_text("Account created successfully")

# Bad: Tests implementation details
expect(User.count).to eq(1)
```

### 2. Use Page Objects for Complex Flows
```ruby
class RegistrationPage
  include Capybara::DSL
  
  def visit_page
    visit new_user_registration_path
  end
  
  def fill_form(email:, password:)
    fill_in "Email", with: email
    fill_in "Password", with: password
  end
  
  def submit
    click_button "Create Account"
  end
end
```

### 3. Handle Asynchronous Operations
```ruby
# Wait for dynamic content
expect(page).to have_text("Loading complete", wait: 10)

# Wait for specific elements
expect(page).to have_css("[data-testid='results']", wait: 5)
```

### 4. Test Error Recovery
```ruby
it "allows user to correct validation errors" do
  submit_invalid_form
  
  expect(page).to have_text("Email is required")
  
  fill_in "Email", with: "valid@example.com"
  click_button "Submit"
  
  expect(page).to have_text("Success")
end
```

## 🔧 IDM Integration

### Adding UI Tests to Feature Memory
```ruby
class FeatureMemories::ContactFormFeature < FeatureMemories::ApplicationFeatureMemory
  ui_testing do
    test_coverage_requirement 95
    mandatory_before_completion true
    test_frameworks :rspec, :capybara, :puppeteer
    
    happy_path "User submits contact form successfully" do
      test_type :system
      user_actions ["visit_contact_page", "fill_form", "submit"]
      expected_outcome "Form submitted with confirmation email"
      components_under_test ["ContactFormComponent"]
      test_file "spec/system/contact_form_spec.rb"
      priority :critical
    end
  end
end
```

### Tracking Test Status
```bash
# Check UI testing status
rails idm:ui_status[contact_form_feature]

# Update test status
rails idm:update_ui_test[contact_form_feature,scenario_id,passed]

# Check completion readiness
rails idm:completion_status[contact_form_feature]
```

## 📊 Test Execution and Reporting

### Continuous Integration
- All UI tests must pass before deployment
- Critical tests block feature completion
- Performance tests verify within thresholds
- Accessibility tests ensure compliance

### Test Reporting
- Screenshot capture for visual verification
- Performance metrics logging
- Accessibility violation reporting
- Coverage reports integration

### Failure Investigation
1. Capture detailed error information
2. Take failure screenshots
3. Log browser console errors
4. Document in IDM troubleshooting section

## 🚫 Common Pitfalls to Avoid

### 1. Testing Implementation Instead of Behavior
```ruby
# Wrong
expect(page).to have_css(".hidden")

# Right  
expect(page).not_to have_text("Sensitive Information")
```

### 2. Brittle Selectors
```ruby
# Fragile
find(".container > div:nth-child(3) > button")

# Robust
find('[data-testid="submit-button"]')
```

### 3. Missing Wait Conditions
```ruby
# Can cause flaky tests
click_button "Load Data"
expect(page).to have_text("Data loaded")

# Reliable
click_button "Load Data"
expect(page).to have_text("Data loaded", wait: 10)
```

### 4. Insufficient Error Testing
- Don't only test happy paths
- Include network failures
- Test validation errors
- Verify error recovery

## ✅ Completion Checklist

Before marking UI testing as complete:

- [ ] All test types implemented (happy path, edge cases, errors, accessibility, performance)
- [ ] Test coverage meets minimum requirement (90%)
- [ ] All critical tests pass
- [ ] Accessibility requirements verified
- [ ] Performance thresholds met
- [ ] Test files properly organized and documented
- [ ] IDM ui_testing block updated with all scenarios
- [ ] Test status updated in IDM
- [ ] Screenshots captured for complex flows

## 🔄 Maintenance and Updates

### Regular Test Maintenance
- Update tests when UI changes
- Refactor tests for better maintainability
- Remove obsolete tests
- Update test data as needed

### Performance Monitoring
- Track test execution times
- Monitor for flaky tests
- Update performance thresholds based on real usage
- Optimize slow tests

---

**Remember**: UI testing is not optional - it's a critical component of feature quality assurance and user experience validation. Every feature must meet these testing standards before completion.