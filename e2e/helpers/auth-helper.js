/**
 * Authentication Helper
 * 
 * Provides reusable authentication utilities that can be used
 * across multiple tests. This prevents code duplication and
 * makes authentication setup consistent.
 * 
 * Senior Developer Note: Helper classes like this are where you
 * put commonly used test setup/teardown logic that multiple
 * test files need.
 */

const LoginPage = require('../pages/login-page');

class AuthHelper {
  /**
   * Login as the test user
   * @param {Page} page - Puppeteer page instance
   * @param {boolean} rememberMe - Whether to check remember me
   */
  static async loginAsTestUser(page, rememberMe = false) {
    const loginPage = new LoginPage(page);
    await loginPage.navigateToSignIn();
    
    const result = await loginPage.loginAsTestUser();
    
    if (!result.success) {
      throw new Error(`Login failed: ${result.error}`);
    }
    
    // Verify we're redirected to the expected page
    await page.waitForURL('**/companies', { timeout: 10000 });
    
    console.log('✅ Successfully logged in as test user');
    return result;
  }

  /**
   * Login as the admin user
   * @param {Page} page - Puppeteer page instance
   */
  static async loginAsAdmin(page) {
    const loginPage = new LoginPage(page);
    await loginPage.navigateToSignIn();
    
    const result = await loginPage.loginAsAdmin();
    
    if (!result.success) {
      throw new Error(`Admin login failed: ${result.error}`);
    }
    
    await page.waitForURL('**/companies', { timeout: 10000 });
    
    console.log('✅ Successfully logged in as admin user');
    return result;
  }

  /**
   * Logout current user
   * @param {Page} page - Puppeteer page instance
   */
  static async logout(page) {
    try {
      // Look for user menu or logout button
      const userMenuSelector = '[data-testid="user-menu"], .dropdown-toggle, .nav-user';
      const logoutSelector = 'a:has-text("Logout"), a:has-text("Sign out"), button:has-text("Logout")';
      
      // Try to find and click user menu first
      const userMenu = await page.$(userMenuSelector);
      if (userMenu) {
        await page.click(userMenuSelector);
        await page.waitForTimeout(500); // Wait for dropdown to open
      }
      
      // Click logout
      await page.click(logoutSelector);
      
      // Wait for redirect to login page
      await page.waitForURL('**/users/sign_in', { timeout: 10000 });
      
      console.log('✅ Successfully logged out');
    } catch (error) {
      console.warn('⚠️ Logout failed, might already be logged out:', error.message);
    }
  }

  /**
   * Check if user is currently logged in
   * @param {Page} page - Puppeteer page instance
   */
  static async isLoggedIn(page) {
    try {
      // Check if we can find user-specific elements
      const userIndicators = [
        '[data-testid="user-menu"]',
        '.nav-user',
        '.dropdown-toggle:has-text("Profile")',
        'a:has-text("Logout")'
      ];
      
      for (const selector of userIndicators) {
        const element = await page.$(selector);
        if (element && await element.isVisible()) {
          return true;
        }
      }
      
      // Check URL - if we're on login page, we're not logged in
      const currentUrl = page.url();
      if (currentUrl.includes('/users/sign_in')) {
        return false;
      }
      
      // Try to access a protected page
      await page.goto(`${global.TEST_CONFIG.baseUrl}/companies`, { waitUntil: 'networkidle0' });
      
      // If we're redirected to login, we're not logged in
      const finalUrl = page.url();
      return !finalUrl.includes('/users/sign_in');
      
    } catch (error) {
      console.warn('⚠️ Could not determine login status:', error.message);
      return false;
    }
  }

  /**
   * Ensure user is logged in, login if necessary
   * @param {Page} page - Puppeteer page instance
   * @param {string} userType - 'test' or 'admin'
   */
  static async ensureLoggedIn(page, userType = 'test') {
    const isLoggedIn = await this.isLoggedIn(page);
    
    if (!isLoggedIn) {
      console.log(`🔐 User not logged in, logging in as ${userType} user...`);
      
      if (userType === 'admin') {
        await this.loginAsAdmin(page);
      } else {
        await this.loginAsTestUser(page);
      }
    } else {
      console.log('✅ User already logged in');
    }
  }

  /**
   * Get current user info if available
   * @param {Page} page - Puppeteer page instance
   */
  static async getCurrentUser(page) {
    try {
      // Look for user name in common locations
      const userSelectors = [
        '[data-testid="user-name"]',
        '.user-name',
        '.nav-user .dropdown-toggle',
        '.user-info .name'
      ];
      
      for (const selector of userSelectors) {
        const element = await page.$(selector);
        if (element) {
          const text = await element.textContent();
          if (text && text.trim()) {
            return text.trim();
          }
        }
      }
      
      return null;
    } catch (error) {
      console.warn('⚠️ Could not get current user info:', error.message);
      return null;
    }
  }

  /**
   * Test login with invalid credentials
   * @param {Page} page - Puppeteer page instance
   * @param {string} email - Invalid email
   * @param {string} password - Invalid password
   */
  static async testInvalidLogin(page, email = 'invalid@example.com', password = 'wrongpassword') {
    const loginPage = new LoginPage(page);
    await loginPage.navigateToSignIn();
    
    const result = await loginPage.login(email, password);
    
    // Should fail
    if (result.success) {
      throw new Error('Expected login to fail with invalid credentials');
    }
    
    console.log('✅ Invalid login correctly rejected');
    return result;
  }
}

module.exports = AuthHelper;