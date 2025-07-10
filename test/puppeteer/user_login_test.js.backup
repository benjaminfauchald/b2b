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
    await page.click('input[type="submit"]');
    
    // Wait for redirect after login
    await page.waitForNavigation({ timeout: 10000 });
    
    // Take screenshot after login
    await page.screenshot({ 
      path: `/tmp/login_${isAdmin ? 'admin' : 'test'}_after.png`,
      fullPage: false 
    });
    
    // Verify successful login by checking current URL
    const currentUrl = page.url();
    console.log(`  🌐 Current URL after login: ${currentUrl}`);
    
    // Check if we're redirected away from login page (successful login)
    if (currentUrl.includes('/users/sign_in')) {
      throw new Error(`Login failed - still on login page for ${email}`);
    }
    
    // Check if we can access user menu or profile (indicates successful login)
    const userMenuExists = await page.$('[data-test="user-menu"], .user-menu, [href="/users/edit"], [href*="sign_out"]');
    if (!userMenuExists) {
      console.log(`  ⚠️  User menu not found, checking for other login indicators...`);
      
      // Alternative check: look for elements that only appear when logged in
      const loggedInElements = await page.$$eval('body *', elements => {
        return elements.some(el => 
          el.textContent.includes('Sign out') || 
          el.textContent.includes('Profile') ||
          el.textContent.includes('Dashboard') ||
          el.href && el.href.includes('sign_out')
        );
      });
      
      if (!loggedInElements) {
        throw new Error(`Could not verify successful login for ${email}`);
      }
    }
    
    // For admin user, check if admin features are accessible
    if (isAdmin) {
      console.log(`  👑 Verifying admin access...`);
      
      // Check if user is recognized as admin (this depends on your app's admin detection)
      const isAdminUser = await page.evaluate(() => {
        // Look for admin-specific elements or text
        const bodyText = document.body.textContent || '';
        return bodyText.includes('Admin') || 
               document.querySelector('[data-admin], .admin-panel, .admin-nav') !== null ||
               window.location.href.includes('admin');
      });
      
      console.log(`  👑 Admin status detected: ${isAdminUser}`);
    }
    
    console.log(`  ✅ ${expectedUserType} login successful!`);
    console.log(`  📸 Screenshots saved:`);
    console.log(`    - /tmp/login_${isAdmin ? 'admin' : 'test'}_before.png`);
    console.log(`    - /tmp/login_${isAdmin ? 'admin' : 'test'}_after.png`);
    
    // Sign out to clean up for next test
    console.log(`  🚪 Signing out...`);
    const signOutLink = await page.$('[href*="sign_out"], a[data-method="delete"]');
    if (signOutLink) {
      await signOutLink.click();
      await page.waitForNavigation({ timeout: 5000 }).catch(() => {
        console.log(`  ⚠️  Sign out navigation timeout (may be normal)`);
      });
    } else {
      console.log(`  ⚠️  Sign out link not found, navigating to sign out manually...`);
      await page.goto('https://local.connectica.no/users/sign_out');
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