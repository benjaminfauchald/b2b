# E2E Testing Setup Plan

## Overview
Setup a comprehensive End-to-End (E2E) testing system using Jest + Puppeteer to ensure all application functionality works properly before production deployment.

## Current State Analysis

### Existing Testing Infrastructure
- **RSpec Tests**: 700+ examples covering unit, integration, and system tests
- **Puppeteer Tests**: 25+ existing tests in `/test/puppeteer/` directory
- **Current Config**: `test/puppeteer/puppeteer_config.js` with 1920x1080 viewport
- **Rails Testing**: Comprehensive controller, model, and component test coverage

### Existing Puppeteer Tests
- User authentication (login/signup)
- LinkedIn discovery workflows
- Domain queue management
- Company financial data processing
- Web discovery batch operations

## Problems with Current Setup

1. **No Standardized Framework**: Tests are standalone scripts without test runner
2. **No CI/CD Integration**: Tests aren't run automatically in deployment pipeline
3. **Inconsistent Structure**: No unified test organization or reporting
4. **Manual Execution**: Tests must be run individually, no test suites
5. **No Test Data Management**: Each test creates its own data setup
6. **Limited Coverage**: Missing critical workflow tests

## Proposed Solution: Jest + Puppeteer E2E Framework

### Why Jest + Puppeteer?
- **Industry Standard**: Widely adopted for E2E testing
- **Rich Ecosystem**: Extensive plugins and matchers
- **Parallel Execution**: Can run tests concurrently
- **Great Reporting**: Built-in test results and coverage
- **CI/CD Ready**: Easy integration with GitHub Actions
- **Rails Compatible**: Works alongside existing RSpec tests

## Implementation Plan

### Phase 1: Framework Setup
1. **Create `/e2e` directory structure**
2. **Install Jest and Jest-Puppeteer**
3. **Configure Jest for Puppeteer integration**
4. **Setup test data management**
5. **Create base test classes and utilities**

### Phase 2: Test Migration and Enhancement
1. **Migrate existing Puppeteer tests to Jest**
2. **Create comprehensive test suites**
3. **Add missing critical workflow tests**
4. **Implement Page Object Model pattern**

### Phase 3: CI/CD Integration
1. **Update GitHub Actions workflow**
2. **Add E2E test stage before deployment**
3. **Configure test reporting and notifications**
4. **Setup test data seeding for CI**

## Directory Structure

```
e2e/
├── __tests__/
│   ├── auth/
│   │   ├── login.test.js
│   │   └── signup.test.js
│   ├── companies/
│   │   ├── linkedin-discovery.test.js
│   │   ├── postal-code-search.test.js
│   │   └── financial-data.test.js
│   ├── domains/
│   │   ├── queue-management.test.js
│   │   └── web-discovery.test.js
│   ├── people/
│   │   ├── profile-extraction.test.js
│   │   └── email-verification.test.js
│   └── workflows/
│       ├── complete-company-workflow.test.js
│       └── data-import-workflow.test.js
├── config/
│   ├── jest.config.js
│   ├── puppeteer.config.js
│   └── test-data.js
├── helpers/
│   ├── auth-helper.js
│   ├── db-helper.js
│   ├── screenshot-helper.js
│   └── wait-helper.js
├── pages/
│   ├── base-page.js
│   ├── login-page.js
│   ├── companies-page.js
│   ├── domains-page.js
│   └── people-page.js
├── fixtures/
│   ├── test-users.json
│   ├── sample-companies.json
│   └── sample-domains.json
└── package.json
```

## Test Categories

### 1. Authentication Tests
- User login with valid credentials
- User login with invalid credentials
- User signup flow
- Password reset flow
- OAuth authentication (GitHub)

### 2. Core Functionality Tests
- **Companies**: CRUD operations, search, filtering
- **Domains**: Import, queue management, testing
- **People**: Profile extraction, email verification

### 3. Service Integration Tests
- LinkedIn Discovery workflows
- Financial data processing
- Queue management systems
- Service audit logging

### 4. UI/UX Tests
- Form validation and error handling
- Toast notifications
- Loading states and spinners
- Responsive design elements

### 5. End-to-End Workflow Tests
- Complete company data enrichment workflow
- Domain import to processing pipeline
- People extraction and verification pipeline

## Configuration Details

### Jest Configuration
```javascript
// e2e/config/jest.config.js
module.exports = {
  preset: 'jest-puppeteer',
  testMatch: ['<rootDir>/__tests__/**/*.test.js'],
  setupFilesAfterEnv: ['<rootDir>/config/setup.js'],
  testTimeout: 60000,
  maxWorkers: 2, // Limit concurrent tests
  reporters: [
    'default',
    ['jest-html-reporters', {
      publicPath: './e2e-reports',
      filename: 'report.html'
    }]
  ]
};
```

### Puppeteer Configuration
```javascript
// e2e/config/puppeteer.config.js
module.exports = {
  launch: {
    headless: process.env.CI === 'true',
    defaultViewport: { width: 1920, height: 1080 },
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--window-size=1920,1080',
      '--start-maximized'
    ]
  }
};
```

## E2E Testing Best Practices

### 📋 Core Testing Principles

#### 1. **Test Pyramid Adherence**
- **Unit Tests (70%)**: Fast, isolated, comprehensive coverage
- **Integration Tests (20%)**: Service interactions, API endpoints
- **E2E Tests (10%)**: Critical user journeys, high-value workflows
- **Principle**: E2E tests should focus on business-critical paths, not comprehensive feature coverage

#### 2. **User-Centric Testing Approach**
- Test from user perspective, not implementation details
- Focus on complete user journeys and workflows
- Validate actual business value delivery
- Test realistic user scenarios and edge cases

#### 3. **Production-Like Environment**
- Use staging environment that mirrors production
- Test with realistic data volumes and scenarios
- Include third-party service integrations
- Validate performance under realistic conditions

### 🔧 Technical Best Practices

#### 1. **Reliable Element Selection**
```javascript
// ✅ Good - Stable, semantic selectors
await page.click('[data-testid="submit-button"]');
await page.click('button[aria-label="Save changes"]');
await page.click('text=Submit Order');

// ❌ Avoid - Brittle, implementation-dependent selectors
await page.click('.btn-primary.form-submit.css-123abc');
await page.click('div > div:nth-child(3) > button');
```

#### 2. **Robust Wait Strategies**
```javascript
// ✅ Wait for specific conditions
await page.waitForSelector('[data-testid="success-message"]');
await page.waitForFunction(() => document.readyState === 'complete');
await page.waitForResponse(response => response.url().includes('/api/submit'));

// ❌ Avoid arbitrary timeouts
await page.waitForTimeout(5000); // Flaky and slow
```

#### 3. **Effective Error Handling**
```javascript
// ✅ Comprehensive error context
try {
  await page.click('[data-testid="submit-button"]');
  await page.waitForSelector('[data-testid="success-message"]', { timeout: 10000 });
} catch (error) {
  await page.screenshot({ path: `error-${Date.now()}.png` });
  console.error('Submit failed:', error.message);
  throw error;
}
```

#### 4. **Test Isolation and Independence**
```javascript
// ✅ Each test is independent
describe('User Management', () => {
  beforeEach(async () => {
    await DatabaseHelper.seedTestUser();
    await page.goto('/login');
    await AuthHelper.loginAsTestUser(page);
  });

  afterEach(async () => {
    await DatabaseHelper.cleanupTestData();
  });
});
```

### 🏗️ Architectural Best Practices

#### 1. **Page Object Model (POM)**
```javascript
// ✅ Encapsulate page logic
class LoginPage {
  constructor(page) {
    this.page = page;
    this.emailField = '[data-testid="email-input"]';
    this.passwordField = '[data-testid="password-input"]';
    this.submitButton = '[data-testid="login-button"]';
    this.errorMessage = '[data-testid="error-message"]';
  }

  async login(email, password) {
    await this.page.fill(this.emailField, email);
    await this.page.fill(this.passwordField, password);
    await this.page.click(this.submitButton);
    await this.page.waitForNavigation();
  }

  async getErrorMessage() {
    return this.page.textContent(this.errorMessage);
  }
}
```

#### 2. **Reusable Test Utilities**
```javascript
// ✅ Common functionality abstracted
class TestHelpers {
  static async waitForApiCall(page, apiPath) {
    return page.waitForResponse(response => 
      response.url().includes(apiPath) && response.status() === 200
    );
  }

  static async takeDebugScreenshot(page, testName) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    await page.screenshot({ 
      path: `screenshots/${testName}-${timestamp}.png`,
      fullPage: true 
    });
  }
}
```

#### 3. **Test Data Management**
```javascript
// ✅ Centralized test data
class TestDataFactory {
  static createTestUser(overrides = {}) {
    return {
      email: 'test@example.com',
      password: 'TestPassword123!',
      firstName: 'Test',
      lastName: 'User',
      ...overrides
    };
  }

  static async seedCompanyData(count = 10) {
    const companies = Array.from({ length: count }, (_, i) => ({
      name: `Test Company ${i}`,
      domain: `testcompany${i}.com`,
      revenue: Math.floor(Math.random() * 1000000)
    }));

    return DatabaseHelper.createCompanies(companies);
  }
}
```

### 📊 Performance Best Practices

#### 1. **Optimized Test Execution**
```javascript
// ✅ Parallel-safe tests
module.exports = {
  preset: 'jest-puppeteer',
  maxWorkers: '50%', // Use half of available CPU cores
  testTimeout: 60000,
  setupFilesAfterEnv: ['<rootDir>/config/setup.js'],
  globalSetup: '<rootDir>/config/global-setup.js',
  globalTeardown: '<rootDir>/config/global-teardown.js'
};
```

#### 2. **Browser Resource Management**
```javascript
// ✅ Efficient browser usage
describe('Test Suite', () => {
  let browser, page;

  beforeAll(async () => {
    browser = await puppeteer.launch({
      headless: process.env.CI === 'true',
      defaultViewport: { width: 1920, height: 1080 }
    });
  });

  beforeEach(async () => {
    page = await browser.newPage();
    // Block unnecessary resources in CI
    if (process.env.CI) {
      await page.setRequestInterception(true);
      page.on('request', (req) => {
        if (req.resourceType() === 'image' || req.resourceType() === 'font') {
          req.abort();
        } else {
          req.continue();
        }
      });
    }
  });

  afterEach(async () => {
    await page.close();
  });

  afterAll(async () => {
    await browser.close();
  });
});
```

### 🛡️ Reliability Best Practices

#### 1. **Flaky Test Prevention**
```javascript
// ✅ Retry strategies for unstable operations
async function retryOperation(operation, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await operation();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)));
    }
  }
}

// Usage
await retryOperation(async () => {
  await page.click('[data-testid="submit-button"]');
  await page.waitForSelector('[data-testid="success-message"]');
});
```

#### 2. **Network Stability**
```javascript
// ✅ Handle network conditions
await page.setDefaultNavigationTimeout(30000);
await page.setDefaultTimeout(10000);

// Wait for network idle before proceeding
await page.goto(url, { waitUntil: 'networkidle0' });
```

#### 3. **State Verification**
```javascript
// ✅ Verify application state before actions
async function ensureElementState(page, selector, expectedState) {
  const element = await page.$(selector);
  if (!element) {
    throw new Error(`Element ${selector} not found`);
  }
  
  const isEnabled = await element.isEnabled();
  if (expectedState === 'enabled' && !isEnabled) {
    throw new Error(`Element ${selector} is not enabled`);
  }
}

// Usage
await ensureElementState(page, '[data-testid="submit-button"]', 'enabled');
await page.click('[data-testid="submit-button"]');
```

### 📝 Test Organization Best Practices

#### 1. **Descriptive Test Names**
```javascript
// ✅ Clear, behavior-focused test names
describe('User Authentication', () => {
  test('should redirect to dashboard after successful login with valid credentials', async () => {
    // Test implementation
  });

  test('should display error message when login fails with invalid password', async () => {
    // Test implementation
  });

  test('should lock account after 5 consecutive failed login attempts', async () => {
    // Test implementation
  });
});
```

#### 2. **Test Documentation**
```javascript
// ✅ Self-documenting tests with clear steps
test('should complete order checkout workflow', async () => {
  // Given: User is logged in and has items in cart
  await AuthHelper.loginAsTestUser(page);
  await CartHelper.addItemsToCart(page, ['item1', 'item2']);

  // When: User proceeds through checkout
  await page.click('[data-testid="checkout-button"]');
  await CheckoutPage.fillShippingInfo(page, TestData.validAddress);
  await CheckoutPage.selectPaymentMethod(page, 'credit-card');
  await CheckoutPage.submitOrder(page);

  // Then: Order confirmation is displayed
  await expect(page.locator('[data-testid="order-confirmation"]')).toBeVisible();
  const orderNumber = await page.textContent('[data-testid="order-number"]');
  expect(orderNumber).toMatch(/^ORD-\d{8}$/);
});
```

#### 3. **Test Data Management**
```javascript
// ✅ Isolated test data per test
beforeEach(async () => {
  await DatabaseHelper.cleanDatabase();
  testUser = await TestDataFactory.createUser();
  testCompanies = await TestDataFactory.createCompanies(5);
});

afterEach(async () => {
  await DatabaseHelper.cleanupTestData([testUser.id]);
});
```

### 🔍 Debugging Best Practices

#### 1. **Comprehensive Logging**
```javascript
// ✅ Detailed logging for debugging
class TestLogger {
  static async logTestStep(step, details = {}) {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${step}`, details);
  }

  static async logPageConsole(page) {
    page.on('console', msg => {
      console.log(`[PAGE ${msg.type()}] ${msg.text()}`);
    });
  }

  static async logNetworkActivity(page) {
    page.on('response', response => {
      if (response.status() >= 400) {
        console.error(`[NETWORK ERROR] ${response.url()} - ${response.status()}`);
      }
    });
  }
}
```

#### 2. **Screenshot and Video Evidence**
```javascript
// ✅ Capture evidence on failures
test('should process payment successfully', async () => {
  try {
    // Test steps
    await processPayment();
  } catch (error) {
    // Capture evidence
    await page.screenshot({ 
      path: `failures/${test.getFullName()}-${Date.now()}.png`,
      fullPage: true 
    });
    
    // Log page state
    const url = page.url();
    const title = await page.title();
    console.error(`Test failed on page: ${url} (${title})`);
    
    throw error;
  }
});
```

### 🚀 CI/CD Integration Best Practices

#### 1. **Environment Configuration**
```javascript
// ✅ Environment-specific configuration
const config = {
  baseUrl: process.env.BASE_URL || 'http://localhost:3000',
  headless: process.env.CI === 'true',
  timeout: process.env.CI === 'true' ? 60000 : 30000,
  retries: process.env.CI === 'true' ? 2 : 0
};
```

#### 2. **Test Reporting**
```javascript
// ✅ Comprehensive test reporting
module.exports = {
  reporters: [
    'default',
    ['jest-html-reporters', {
      publicPath: './e2e-reports',
      filename: 'report.html',
      expand: true
    }],
    ['jest-junit', {
      outputDirectory: './e2e-reports',
      outputName: 'junit.xml'
    }]
  ]
};
```

### ⚠️ Anti-Patterns to Avoid

#### 1. **Don't Test Implementation Details**
```javascript
// ❌ Testing internal state
expect(component.state.isLoading).toBe(false);

// ✅ Test user-visible behavior
await expect(page.locator('[data-testid="loading-spinner"]')).not.toBeVisible();
```

#### 2. **Don't Use Arbitrary Waits**
```javascript
// ❌ Fixed timeouts
await page.waitForTimeout(5000);

// ✅ Conditional waits
await page.waitForSelector('[data-testid="results-loaded"]');
```

#### 3. **Don't Create Interdependent Tests**
```javascript
// ❌ Tests that depend on each other
test('creates user', async () => { /* creates user with ID 123 */ });
test('updates user', async () => { /* assumes user 123 exists */ });

// ✅ Independent tests
test('updates user', async () => {
  const user = await TestDataFactory.createUser();
  // test uses the user created in this test
});
```

#### 4. **Don't Test Everything Through the UI**
```javascript
// ❌ Setting up complex state through UI
await createUser();
await createCompany();
await assignUserToCompany();
await setCompanySettings();
await page.goto('/dashboard');

// ✅ Setup through API/database, test UI behavior
await DatabaseHelper.seedComplexTestScenario();
await page.goto('/dashboard');
await expect(page.locator('[data-testid="dashboard-content"]')).toBeVisible();
```

### 📚 Documentation Best Practices

#### 1. **Test Documentation**
- Document test objectives and success criteria
- Explain complex test scenarios and business logic
- Maintain test data requirements and dependencies
- Keep troubleshooting guides for common issues

#### 2. **Code Comments**
```javascript
// ✅ Meaningful comments for complex logic
test('should handle concurrent user sessions', async () => {
  // Create two browser contexts to simulate different users
  const context1 = await browser.newContext();
  const context2 = await browser.newContext();
  
  // Both users access the same resource simultaneously
  // This tests our application's handling of race conditions
  const [result1, result2] = await Promise.all([
    context1.newPage().then(page => performAction(page)),
    context2.newPage().then(page => performAction(page))
  ]);
  
  // Verify that both operations completed successfully
  // without data corruption or conflicts
  expect(result1.success).toBe(true);
  expect(result2.success).toBe(true);
});
```

These best practices ensure our E2E tests are reliable, maintainable, and provide maximum value for catching real user issues before production deployment.

## Test Implementation Strategy

### 1. Page Object Model
Create reusable page objects for consistent test interactions:

```javascript
// e2e/pages/login-page.js
class LoginPage {
  constructor(page) {
    this.page = page;
  }

  async navigateTo() {
    await this.page.goto('https://local.connectica.no/users/sign_in');
  }

  async fillCredentials(email, password) {
    await this.page.fill('input[type="email"]', email);
    await this.page.fill('input[type="password"]', password);
  }

  async submit() {
    await this.page.click('button[type="submit"]');
    await this.page.waitForNavigation();
  }
}
```

### 2. Test Data Management
```javascript
// e2e/helpers/db-helper.js
class DatabaseHelper {
  static async seedTestData() {
    // Setup test users, companies, domains
  }

  static async cleanupTestData() {
    // Remove test data after tests
  }
}
```

### 3. Utility Helpers
```javascript
// e2e/helpers/auth-helper.js
class AuthHelper {
  static async loginAsTestUser(page) {
    const loginPage = new LoginPage(page);
    await loginPage.navigateTo();
    await loginPage.fillCredentials('test@test.no', 'CodemyFTW2');
    await loginPage.submit();
  }
}
```

## Sample Test Implementation

### Login Test (Proof of Concept)
```javascript
// e2e/__tests__/auth/login.test.js
describe('User Authentication', () => {
  let page;

  beforeAll(async () => {
    page = await global.__BROWSER__.newPage();
    await page.setViewport({ width: 1920, height: 1080 });
  });

  afterAll(async () => {
    await page.close();
  });

  test('should login with valid credentials', async () => {
    // Navigate to login page
    await page.goto('https://local.connectica.no/users/sign_in');
    
    // Fill credentials
    await page.fill('input[type="email"]', 'test@test.no');
    await page.fill('input[type="password"]', 'CodemyFTW2');
    
    // Submit form
    await page.click('button:has-text("Sign in")');
    
    // Verify successful login
    await page.waitForURL('**/companies');
    await expect(page).toHaveURL(/companies/);
    
    // Verify user is logged in
    const userMenu = await page.locator('[data-testid="user-menu"]');
    await expect(userMenu).toBeVisible();
  });

  test('should show error with invalid credentials', async () => {
    await page.goto('https://local.connectica.no/users/sign_in');
    
    await page.fill('input[type="email"]', 'invalid@example.com');
    await page.fill('input[type="password"]', 'wrongpassword');
    
    await page.click('button:has-text("Sign in")');
    
    // Verify error message
    const errorMessage = await page.locator('.alert-danger');
    await expect(errorMessage).toBeVisible();
    await expect(errorMessage).toContainText('Invalid email or password');
  });
});
```

## CI/CD Integration

### GitHub Actions Update
```yaml
# .github/workflows/main.yml (addition)
  e2e-tests:
    runs-on: ubuntu-latest
    needs: [test]
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - name: Install E2E dependencies
        run: cd e2e && npm install
      - name: Setup test database
        run: |
          RAILS_ENV=test bin/rails db:migrate
          RAILS_ENV=test bin/rails db:seed
      - name: Start Rails server
        run: |
          RAILS_ENV=test bin/rails server -d
          sleep 10
      - name: Run E2E tests
        run: cd e2e && npm test
      - name: Upload test reports
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: e2e-reports
          path: e2e/e2e-reports/
```

## Quality Assurance

### Test Coverage Goals
- **Authentication**: 100% of auth flows
- **Core CRUD**: 90% of create/read/update/delete operations  
- **Service Integrations**: 80% of external service workflows
- **Critical Workflows**: 100% of business-critical paths

### Performance Benchmarks
- Tests should complete in < 10 minutes total
- Individual test timeout: 60 seconds
- Page load assertions: < 5 seconds
- Form submission assertions: < 3 seconds

### Reliability Standards
- Tests must pass consistently (95%+ success rate)
- Flaky tests must be fixed or disabled
- Clear error messages for debugging
- Screenshot capture on failures

## Migration from Existing Tests

### Phase 1: Direct Migration
1. Convert `user_login_test.js` → `e2e/__tests__/auth/login.test.js`
2. Convert `linkedin_discovery_test.js` → `e2e/__tests__/companies/linkedin-discovery.test.js`
3. Convert `domain_queue_integration_test.js` → `e2e/__tests__/domains/queue-management.test.js`

### Phase 2: Enhancement
1. Add comprehensive error handling tests
2. Create multi-step workflow tests
3. Add accessibility testing with axe-puppeteer
4. Implement visual regression testing

## Success Criteria

### Technical Requirements
- ✅ Jest + Puppeteer framework fully configured
- ✅ All existing Puppeteer tests migrated and enhanced
- ✅ Page Object Model implemented
- ✅ Test data management system
- ✅ CI/CD integration with deployment gates

### Quality Requirements
- ✅ 90%+ test coverage of critical workflows
- ✅ Tests complete in < 10 minutes
- ✅ 95%+ test reliability rate
- ✅ Clear documentation and examples

### User Requirements
- ✅ Login workflow fully tested and reliable
- ✅ All major features have E2E coverage
- ✅ Tests catch regressions before production
- ✅ Easy to add new tests for features

## Risk Mitigation

### Technical Risks
- **Flaky Tests**: Implement robust wait strategies and retries
- **Performance**: Use parallel execution and optimized selectors
- **Maintenance**: Page Object Model reduces test brittleness

### Operational Risks
- **CI/CD Delays**: Set reasonable timeouts and parallel execution
- **Test Data**: Isolated test database with cleanup procedures
- **Environment Issues**: Comprehensive environment validation

## Timeline

### Week 1: Foundation
- Setup Jest + Puppeteer framework
- Create directory structure and configuration
- Implement base classes and utilities

### Week 2: Core Tests
- Migrate and enhance authentication tests
- Create company management test suite
- Implement domain processing tests

### Week 3: Advanced Features
- Add people/profile extraction tests
- Create end-to-end workflow tests
- Implement visual regression testing

### Week 4: Integration & Polish
- CI/CD integration and deployment gates
- Performance optimization and reliability fixes
- Documentation and team training

## Next Steps

1. **Get Approval**: Review and approve this plan
2. **Setup Framework**: Initialize Jest + Puppeteer in `/e2e` directory
3. **Create Login Test**: Implement proof-of-concept login test
4. **Iterate and Expand**: Add more tests based on priority
5. **CI/CD Integration**: Add E2E tests to deployment pipeline

This plan provides a robust, scalable E2E testing solution that will significantly improve application reliability and catch issues before they reach production.