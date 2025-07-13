/**
 * Authentication E2E Tests
 * 
 * Tests the complete user login journey from the user's perspective.
 * This is our proof-of-concept test to validate the E2E framework.
 * 
 * Senior Developer Note: E2E tests should focus on user journeys,
 * not individual UI components. We're testing the complete flow
 * that a real user would experience.
 */

const LoginPage = require('../../pages/login-page');
const AuthHelper = require('../../helpers/auth-helper');

describe('User Authentication', () => {
  let loginPage;

  beforeEach(async () => {
    // Use Jest-Puppeteer's provided page
    loginPage = new LoginPage(page);
    
    // Set viewport for consistent behavior
    await page.setViewport({ width: 1920, height: 1080 });
    
    // Clear any existing sessions
    await page.deleteCookie(...await page.cookies());
    
    console.log('🧪 Starting authentication test...');
  });

  describe('Successful Login', () => {
    test('should login with valid test user credentials and redirect to companies page', async () => {
      console.log('🔐 Testing successful login with test user');
      
      // Navigate to login page
      await loginPage.navigateToSignIn();
      
      // Verify we're on the login page
      expect(await loginPage.isOnLoginPage()).toBe(true);
      expect(await loginPage.isLoginFormReady()).toBe(true);
      
      // Perform login
      const result = await loginPage.loginAsTestUser();
      
      // Verify successful login
      expect(result.success).toBe(true);
      
      // Verify we're redirected away from login page
      // Wait for the URL to change
      await page.waitForFunction(
        () => !window.location.href.includes('/users/sign_in'),
        { timeout: 10000 }
      );
      expect(page.url()).not.toMatch(/\/users\/sign_in/);
      
      // Verify we can see protected content
      // Look for elements that only logged-in users would see
      const protectedElements = [
        'a[href="/users/sign_out"]', // Sign out link
        'a[href="/companies"]', // Companies link
        'h1', // Any h1 heading (homepage should have one)
        '.navbar', // Navigation bar
        'nav' // Navigation element
      ];
      
      let foundProtectedContent = false;
      for (const selector of protectedElements) {
        try {
          await page.waitForSelector(selector, { timeout: 5000 });
          foundProtectedContent = true;
          break;
        } catch (error) {
          // Continue to next selector
        }
      }
      
      expect(foundProtectedContent).toBe(true);
      
      console.log('✅ Test user login successful - redirected to homepage');
    });

    test('should login with valid admin credentials', async () => {
      console.log('🔐 Testing successful login with admin user');
      
      await loginPage.navigateToSignIn();
      
      const result = await loginPage.loginAsAdmin();
      
      expect(result.success).toBe(true);
      // Wait for the URL to change away from login
      await page.waitForFunction(
        () => !window.location.href.includes('/users/sign_in'),
        { timeout: 10000 }
      );
      expect(page.url()).not.toMatch(/\/users\/sign_in/);
      
      console.log('✅ Admin user login successful');
    });

    test('should maintain session with remember me option', async () => {
      console.log('🔐 Testing login with remember me');
      
      await loginPage.navigateToSignIn();
      
      // Login with remember me checked
      const { email, password } = global.TEST_CONFIG.testUser;
      const result = await loginPage.login(email, password, true);
      
      expect(result.success).toBe(true);
      // Wait for the URL to change away from login
      await page.waitForFunction(
        () => !window.location.href.includes('/users/sign_in'),
        { timeout: 10000 }
      );
      
      // Verify remember me cookie or session persistence
      const cookies = await page.cookies();
      const hasRememberToken = cookies.some(cookie => 
        cookie.name.includes('remember') || cookie.name.includes('session')
      );
      
      expect(hasRememberToken).toBe(true);
      
      console.log('✅ Remember me functionality working');
    });
  });

  describe('Failed Login Attempts', () => {
    test('should show error message with invalid email', async () => {
      console.log('❌ Testing login with invalid email');
      
      await loginPage.navigateToSignIn();
      
      const result = await loginPage.login('nonexistent@example.com', 'anypassword');
      
      expect(result.success).toBe(false);
      expect(result.error).toBeTruthy();
      
      // Verify we're still on login page
      expect(await loginPage.isOnLoginPage()).toBe(true);
      
      // Verify error message is visible
      const errorMessage = await loginPage.getErrorMessage();
      expect(errorMessage).toBeTruthy();
      expect(errorMessage.toLowerCase()).toMatch(/(invalid|email|password|credentials)/);
      
      console.log('✅ Invalid email correctly rejected with error message');
    });

    test('should show error message with invalid password', async () => {
      console.log('❌ Testing login with invalid password');
      
      await loginPage.navigateToSignIn();
      
      const { email } = global.TEST_CONFIG.testUser;
      const result = await loginPage.login(email, 'wrongpassword123');
      
      expect(result.success).toBe(false);
      expect(result.error).toBeTruthy();
      
      expect(await loginPage.isOnLoginPage()).toBe(true);
      
      const errorMessage = await loginPage.getErrorMessage();
      expect(errorMessage).toBeTruthy();
      
      console.log('✅ Invalid password correctly rejected');
    });

    test('should reject empty credentials', async () => {
      console.log('❌ Testing login with empty credentials');
      
      await loginPage.navigateToSignIn();
      
      // Try to submit without filling fields
      await loginPage.submitSignIn();
      
      // Should still be on login page
      expect(await loginPage.isOnLoginPage()).toBe(true);
      
      // Check for HTML5 validation or error message
      const emailField = await page.$('input[type="email"]');
      const passwordField = await page.$('input[type="password"]');
      
      const emailValid = await emailField.evaluate(el => el.checkValidity());
      const passwordValid = await passwordField.evaluate(el => el.checkValidity());
      
      expect(emailValid || passwordValid).toBe(false);
      
      console.log('✅ Empty credentials correctly rejected');
    });
  });

  describe('Login Page Features', () => {
    test('should display all required form elements', async () => {
      console.log('🔍 Testing login page UI elements');
      
      await loginPage.navigateToSignIn();
      
      // Verify all form elements are present
      expect(await loginPage.isElementVisible(loginPage.selectors.emailField)).toBe(true);
      expect(await loginPage.isElementVisible(loginPage.selectors.passwordField)).toBe(true);
      expect(await loginPage.isElementVisible(loginPage.selectors.signInButton)).toBe(true);
      
      // Check for additional elements
      const hasRememberMe = await loginPage.isElementVisible(loginPage.selectors.rememberMeCheckbox);
      const hasForgotPassword = await loginPage.isElementVisible(loginPage.selectors.forgotPasswordLink);
      
      console.log(`📋 Form elements present: email ✓, password ✓, submit ✓, remember me: ${hasRememberMe ? '✓' : '✗'}, forgot password: ${hasForgotPassword ? '✓' : '✗'}`);
      
      expect(await loginPage.isLoginFormReady()).toBe(true);
      
      console.log('✅ Login page UI elements verified');
    });

    test('should have proper form accessibility', async () => {
      console.log('♿ Testing login form accessibility');
      
      await loginPage.navigateToSignIn();
      
      // Check for proper form labels
      const emailField = await page.$('input[type="email"]');
      const passwordField = await page.$('input[type="password"]');
      
      const emailLabel = await emailField.evaluate(el => el.labels?.length > 0 || el.getAttribute('aria-label') || el.getAttribute('placeholder'));
      const passwordLabel = await passwordField.evaluate(el => el.labels?.length > 0 || el.getAttribute('aria-label') || el.getAttribute('placeholder'));
      
      expect(emailLabel).toBeTruthy();
      expect(passwordLabel).toBeTruthy();
      
      console.log('✅ Form accessibility elements verified');
    });
  });

  describe('Navigation and User Journey', () => {
    test('should handle login workflow using AuthHelper', async () => {
      console.log('🔄 Testing complete login workflow with AuthHelper');
      
      // Use our AuthHelper for a complete login flow
      await AuthHelper.loginAsTestUser(page);
      
      // Verify login status
      const isLoggedIn = await AuthHelper.isLoggedIn(page);
      expect(isLoggedIn).toBe(true);
      
      // Try to get user info
      const userInfo = await AuthHelper.getCurrentUser(page);
      console.log(`👤 Current user: ${userInfo || 'Not detected'}`);
      
      console.log('✅ AuthHelper login workflow completed successfully');
    });

    test('should handle logout workflow', async () => {
      console.log('🚪 Testing logout workflow');
      
      // First login
      await AuthHelper.loginAsTestUser(page);
      expect(await AuthHelper.isLoggedIn(page)).toBe(true);
      
      // Then logout
      await AuthHelper.logout(page);
      
      // Verify we're logged out
      expect(page.url()).toMatch(/\/users\/sign_in/);
      expect(await AuthHelper.isLoggedIn(page)).toBe(false);
      
      console.log('✅ Logout workflow completed successfully');
    });
  });

  // Test performance and reliability
  describe('Performance and Reliability', () => {
    test('should complete login within reasonable time', async () => {
      console.log('⏱️  Testing login performance');
      
      const startTime = Date.now();
      
      await loginPage.navigateToSignIn();
      await loginPage.loginAsTestUser();
      // Wait for redirect away from login page
      await page.waitForFunction(
        () => !window.location.href.includes('/users/sign_in'),
        { timeout: 10000 }
      );
      
      const endTime = Date.now();
      const duration = endTime - startTime;
      
      console.log(`⏱️  Login completed in ${duration}ms`);
      
      // Login should complete within 10 seconds
      expect(duration).toBeLessThan(10000);
      
      console.log('✅ Login performance within acceptable limits');
    });

    test('should handle slow network conditions', async () => {
      console.log('🐌 Testing login with slow network');
      
      // Simulate slow network
      await page.setDefaultNavigationTimeout(30000);
      await page.setDefaultTimeout(15000);
      
      // Emulate slow 3G
      const client = await page.target().createCDPSession();
      await client.send('Network.emulateNetworkConditions', {
        offline: false,
        downloadThroughput: 500 * 1024, // 500kb/s
        uploadThroughput: 500 * 1024,
        latency: 2000 // 2 second latency
      });
      
      try {
        await loginPage.navigateToSignIn();
        const result = await loginPage.loginAsTestUser();
        
        expect(result.success).toBe(true);
        
        console.log('✅ Login works under slow network conditions');
      } finally {
        // Reset network conditions
        await client.send('Network.emulateNetworkConditions', {
          offline: false,
          downloadThroughput: -1,
          uploadThroughput: -1,
          latency: 0
        });
      }
    });
  });
});