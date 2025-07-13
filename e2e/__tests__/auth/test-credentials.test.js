/**
 * Test credentials directly
 */

const LoginPage = require('../../pages/login-page');

describe('Test Credentials', () => {
  let loginPage;

  beforeEach(async () => {
    loginPage = new LoginPage(page);
    await page.setViewport({ width: 1920, height: 1080 });
    await page.deleteCookie(...await page.cookies());
  });

  test('verify test user credentials', async () => {
    console.log('Testing test user credentials...');
    await loginPage.navigateToSignIn();
    
    const { email, password } = global.TEST_CONFIG.testUser;
    console.log(`Email: ${email}, Password: ${password}`);
    
    const result = await loginPage.login(email, password);
    console.log('Result:', result);
    console.log('Current URL:', page.url());
  });

  test('verify admin credentials', async () => {
    console.log('Testing admin credentials...');
    await loginPage.navigateToSignIn();
    
    const { email, password } = global.TEST_CONFIG.adminUser;
    console.log(`Email: ${email}, Password: ${password}`);
    
    const result = await loginPage.login(email, password);
    console.log('Result:', result);
    console.log('Current URL:', page.url());
    
    // Take screenshot
    await page.screenshot({ path: 'screenshots/admin-login-result.png' });
  });
});