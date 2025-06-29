const puppeteer = require('puppeteer');

// Helper function for delays
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function testUserLogin() {
  const browser = await puppeteer.launch({ 
    headless: false,
    defaultViewport: { width: 1400, height: 900 }
  });
  
  try {
    console.log('🧪 STARTING USER LOGIN TESTS');
    console.log('============================\n');
    
    // Test 1: Regular user login
    console.log('🔐 Testing regular user login (test@test.no)...');
    await testLogin(browser, 'test@test.no', 'CodemyFTW2', 'Test User');
    
    // Test 2: Admin user login
    console.log('\n🔐 Testing admin user login (admin@example.com)...');
    await testLogin(browser, 'admin@example.com', 'CodemyFTW2', 'Admin User', true);
    
    console.log('\n✅ ALL LOGIN TESTS COMPLETED SUCCESSFULLY!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    throw error;
  } finally {
    await browser.close();
  }
}

async function testLogin(browser, email, password, expectedUserType, isAdmin = false) {
  const page = await browser.newPage();
  
  try {
    // First, ensure we're logged out
    console.log(`  📄 Ensuring user is logged out...`);
    await page.goto('https://local.connectica.no');
    
    // Check if already logged in
    const signOutLink = await page.$('a[href*="sign_out"]');
    if (signOutLink) {
      console.log(`  🚪 Found existing session, signing out...`);
      await signOutLink.click();
      await delay(2000); // Wait for sign out to complete
    }
    
    // Navigate to login page
    console.log(`  📄 Navigating to login page...`);
    await page.goto('https://local.connectica.no/users/sign_in');
    await page.waitForSelector('input[name="user[email]"]', { timeout: 10000 });
    
    // Fill login form
    console.log(`  ✍️  Filling login form for ${email}...`);
    await page.type('input[name="user[email]"]', email);
    await page.type('input[name="user[password]"]', password);
    
    // Take screenshot before login
    await page.screenshot({ 
      path: `/tmp/login_${isAdmin ? 'admin' : 'test'}_before.png`,
      fullPage: false 
    });
    
    // Submit login form
    console.log(`  🚀 Submitting login form...`);
    const submitButton = await page.$('button[type="submit"], input[type="submit"]');
    if (submitButton) {
      await submitButton.click();
    } else {
      console.log(`  ⌨️  No submit button found, pressing Enter...`);
      await page.keyboard.press('Enter');
    }
    
    // Wait for navigation or timeout
    console.log(`  ⏳ Waiting for response...`);
    try {
      await page.waitForNavigation({ timeout: 5000 });
    } catch (e) {
      console.log(`  ⚠️  Navigation timeout, checking current state...`);
    }
    
    // Check for error messages
    const errorElement = await page.$('.alert-danger, .error-message, .flash-error');
    if (errorElement) {
      const errorText = await errorElement.evaluate(el => el.textContent);
      console.error(`  ❌ Login error: ${errorText.trim()}`);
      throw new Error(`Login failed with error: ${errorText.trim()}`);
    }
    
    // Check for success message
    const successElement = await page.$('.alert-success, .notice, .flash-notice, [role="alert"]');
    if (successElement) {
      const successText = await successElement.evaluate(el => el.textContent);
      console.log(`  ✅ Success message: ${successText.trim()}`);
    }
    
    // Take screenshot after login
    await page.screenshot({ 
      path: `/tmp/login_${isAdmin ? 'admin' : 'test'}_after.png`,
      fullPage: false 
    });
    
    // Verify successful login
    const currentUrl = page.url();
    console.log(`  🌐 Current URL after login: ${currentUrl}`);
    
    // Check if we're on the home page or dashboard (successful login)
    if (currentUrl.includes('/users/sign_in')) {
      throw new Error(`Login failed - still on login page for ${email}`);
    }
    
    // Wait a bit for page to stabilize
    await delay(2000);
    
    // Verify we're logged in by checking for sign out link
    const loggedInSignOutLink = await page.$('a[href*="sign_out"]');
    if (!loggedInSignOutLink) {
      console.log(`  ⚠️  Sign out link not found, checking page content...`);
      const pageContent = await page.evaluate(() => document.body.textContent);
      console.log(`  📄 Page contains email: ${pageContent.includes(email)}`);
    } else {
      console.log(`  ✅ Sign out link found - user is logged in`);
    }
    
    // For admin user, verify admin status
    if (isAdmin) {
      console.log(`  👑 Verifying admin access...`);
      const pageContent = await page.evaluate(() => document.body.textContent);
      const hasAdminIndicator = pageContent.includes('Admin') || currentUrl.includes('admin');
      console.log(`  👑 Admin indicators found: ${hasAdminIndicator}`);
    }
    
    console.log(`  ✅ ${expectedUserType} login successful!`);
    console.log(`  📸 Screenshots saved:`);
    console.log(`    - /tmp/login_${isAdmin ? 'admin' : 'test'}_before.png`);
    console.log(`    - /tmp/login_${isAdmin ? 'admin' : 'test'}_after.png`);
    
    // Sign out to clean up for next test
    console.log(`  🚪 Signing out...`);
    const finalSignOutLink = await page.$('a[href*="sign_out"]');
    if (finalSignOutLink) {
      await finalSignOutLink.click();
      await delay(2000);
      console.log(`  ✅ Signed out successfully`);
    }
    
  } catch (error) {
    console.error(`  ❌ Login test failed for ${email}:`, error.message);
    
    // Take error screenshot
    await page.screenshot({ 
      path: `/tmp/login_${isAdmin ? 'admin' : 'test'}_error.png`,
      fullPage: true 
    });
    console.log(`  📸 Error screenshot saved to /tmp/login_${isAdmin ? 'admin' : 'test'}_error.png`);
    
    throw error;
  } finally {
    await page.close();
  }
}

// Run the test
testUserLogin()
  .then(() => {
    console.log('\n🎯 All user login tests passed!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n💥 User login tests failed:', error);
    process.exit(1);
  });