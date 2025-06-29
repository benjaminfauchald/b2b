const puppeteer = require('puppeteer');

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
      await page.waitForTimeout || (ms => new Promise(resolve => setTimeout(resolve, ms)))(2000); // Wait for sign out to complete
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
    
    // Submit login form - look for any submit button or input
    console.log(`  🚀 Submitting login form...`);
    const submitButton = await page.$('button[type="submit"], input[type="submit"]');
    if (submitButton) {
      await submitButton.click();
    } else {
      // If no submit button found, try pressing Enter
      console.log(`  ⌨️  No submit button found, pressing Enter...`);
      await page.keyboard.press('Enter');
    }
    
    // Wait for either navigation or error message
    console.log(`  ⏳ Waiting for response...`);
    try {
      await Promise.race([
        page.waitForNavigation({ timeout: 10000 }),
        page.waitForSelector('.alert-danger, .error-message, [role="alert"]', { timeout: 5000 })
      ]);
    } catch (e) {
      // If timeout, check current state
      console.log(`  ⚠️  Navigation timeout, checking current state...`);
    }
    
    // Check for error messages (not success messages)
    const errorElement = await page.$('.alert-danger, .error-message, .flash-error');
    if (errorElement) {
      const errorText = await errorElement.evaluate(el => el.textContent);
      console.error(`  ❌ Login error: ${errorText.trim()}`);
      throw new Error(`Login failed with error: ${errorText.trim()}`);
    }
    
    // Check for success message
    const successElement = await page.$('.alert-success, .notice, .flash-notice');
    if (successElement) {
      const successText = await successElement.evaluate(el => el.textContent);
      console.log(`  ✅ Success message: ${successText.trim()}`);
    }
    
    // Take screenshot after login attempt
    await page.screenshot({ 
      path: `/tmp/login_${isAdmin ? 'admin' : 'test'}_after.png`,
      fullPage: false 
    });
    
    // Verify successful login
    const currentUrl = page.url();
    console.log(`  🌐 Current URL after login: ${currentUrl}`);
    
    // Check if we're still on login page
    if (currentUrl.includes('/users/sign_in')) {
      // Double check for error messages
      const pageContent = await page.content();
      if (pageContent.includes('Invalid') || pageContent.includes('error')) {
        throw new Error(`Login failed - invalid credentials for ${email}`);
      }
      throw new Error(`Login failed - still on login page for ${email}`);
    }
    
    // Verify we're logged in by checking for user-specific elements
    await page.waitForTimeout || (ms => new Promise(resolve => setTimeout(resolve, ms)))(2000); // Give page time to fully load
    
    const loggedInIndicators = await page.evaluate(() => {
      const indicators = {
        signOutLink: !!document.querySelector('a[href*="sign_out"]'),
        userEmail: document.body.textContent.includes('test@test.no') || document.body.textContent.includes('admin@example.com'),
        signInLink: !!document.querySelector('a[href*="sign_in"]')
      };
      return indicators;
    });
    
    console.log(`  📊 Login indicators:`, loggedInIndicators);
    
    if (!loggedInIndicators.signOutLink && loggedInIndicators.signInLink) {
      throw new Error(`Login verification failed - no sign out link found for ${email}`);
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
      await page.waitForTimeout || (ms => new Promise(resolve => setTimeout(resolve, ms)))(2000);
    }
    
  } catch (error) {
    console.error(`  ❌ Login test failed for ${email}:`, error.message);
    
    // Take error screenshot
    await page.screenshot({ 
      path: `/tmp/login_${isAdmin ? 'admin' : 'test'}_error.png`,
      fullPage: true 
    });
    console.log(`  📸 Error screenshot saved to /tmp/login_${isAdmin ? 'admin' : 'test'}_error.png`);
    
    // Log page content for debugging
    const pageTitle = await page.title();
    console.log(`  📄 Page title: ${pageTitle}`);
    
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