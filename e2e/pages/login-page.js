/**
 * Login Page Object
 * 
 * Encapsulates all interactions with the login page.
 * This follows the Page Object Model pattern where each page
 * has its own class with methods for user actions.
 * 
 * Senior Developer Note: By centralizing page interactions here,
 * if the login UI changes, we only need to update this one file
 * instead of every test that uses login functionality.
 */

const BasePage = require('./base-page');

class LoginPage extends BasePage {
  constructor(page) {
    super(page);
    
    // Define all selectors used on this page
    // Senior Dev Note: Keeping selectors at the top makes them easy to maintain
    this.selectors = {
      emailField: '#user_email',
      passwordField: '#user_password',
      signInButton: 'input[type="submit"]',
      signUpButton: 'button[type="submit"], input[value="Sign up"]',
      errorMessage: '.alert-danger, .alert.alert-danger, [data-turbo-temporary="true"]',
      successMessage: '.alert-success, .notice, .alert-info',
      forgotPasswordLink: 'a[href*="password/new"]',
      rememberMeCheckbox: '#user_remember_me'
    };
    
    // Page-specific URLs
    this.urls = {
      signIn: `${global.TEST_CONFIG.baseUrl}/users/sign_in`,
      signUp: `${global.TEST_CONFIG.baseUrl}/users/sign_up`
    };
  }

  /**
   * Navigate to the sign-in page
   */
  async navigateToSignIn() {
    await this.navigateTo(this.urls.signIn);
    await this.waitForElement(this.selectors.emailField);
  }

  /**
   * Navigate to the sign-up page
   */
  async navigateToSignUp() {
    await this.navigateTo(this.urls.signUp);
    await this.waitForElement(this.selectors.emailField);
  }

  /**
   * Fill in the login credentials
   * @param {string} email - User's email address
   * @param {string} password - User's password
   */
  async fillCredentials(email, password) {
    await this.fillField(this.selectors.emailField, email);
    await this.fillField(this.selectors.passwordField, password);
  }

  /**
   * Submit the login form
   */
  async submitSignIn() {
    await this.clickElement(this.selectors.signInButton);
  }

  /**
   * Submit the signup form
   */
  async submitSignUp() {
    await this.clickElement(this.selectors.signUpButton);
  }

  /**
   * Complete login process with credentials
   * @param {string} email - User's email address
   * @param {string} password - User's password
   * @param {boolean} rememberMe - Whether to check "Remember me"
   */
  async login(email, password, rememberMe = false) {
    await this.fillCredentials(email, password);
    
    if (rememberMe) {
      await this.clickElement(this.selectors.rememberMeCheckbox);
    }
    
    // Start navigation promise before clicking
    const navigationPromise = this.page.waitForNavigation({ 
      waitUntil: 'networkidle0',
      timeout: 5000 
    }).catch(() => null);
    
    await this.submitSignIn();
    
    // Wait for navigation or timeout
    await navigationPromise;
    
    // Wait a bit for any messages to appear
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Check current URL - if we're no longer on sign_in page, login was successful
    const currentUrl = this.page.url();
    if (!currentUrl.includes('/users/sign_in')) {
      return { success: true };
    }
    
    // Still on login page, check for error messages
    const hasError = await this.isElementVisible(this.selectors.errorMessage);
    if (hasError) {
      const errorText = await this.getTextContent(this.selectors.errorMessage);
      return { success: false, error: errorText };
    }
    
    // No navigation and no error message - something went wrong
    return { success: false, error: 'Login failed - no redirect occurred' };
  }

  /**
   * Login with test user credentials
   */
  async loginAsTestUser() {
    const { email, password } = global.TEST_CONFIG.testUser;
    return await this.login(email, password);
  }

  /**
   * Login with admin user credentials
   */
  async loginAsAdmin() {
    const { email, password } = global.TEST_CONFIG.adminUser;
    return await this.login(email, password);
  }

  /**
   * Get error message text if present
   */
  async getErrorMessage() {
    if (await this.isElementVisible(this.selectors.errorMessage)) {
      return await this.getTextContent(this.selectors.errorMessage);
    }
    return null;
  }

  /**
   * Get success message text if present
   */
  async getSuccessMessage() {
    if (await this.isElementVisible(this.selectors.successMessage)) {
      return await this.getTextContent(this.selectors.successMessage);
    }
    return null;
  }

  /**
   * Click forgot password link
   */
  async clickForgotPassword() {
    await this.clickElement(this.selectors.forgotPasswordLink);
    await this.waitForNavigation();
  }

  /**
   * Check if we're currently on the login page
   */
  async isOnLoginPage() {
    const currentUrl = this.page.url();
    return currentUrl.includes('/users/sign_in');
  }

  /**
   * Check if login form is visible and ready
   */
  async isLoginFormReady() {
    const emailVisible = await this.isElementVisible(this.selectors.emailField);
    const passwordVisible = await this.isElementVisible(this.selectors.passwordField);
    const buttonVisible = await this.isElementVisible(this.selectors.signInButton);
    
    return emailVisible && passwordVisible && buttonVisible;
  }
}

module.exports = LoginPage;