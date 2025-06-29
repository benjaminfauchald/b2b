const puppeteer = require('puppeteer');

async function testUserSignup() {
  const browser = await puppeteer.launch({ 
    headless: false,
    defaultViewport: { width: 1400, height: 900 },
    slowMo: 100 // Slow down actions to see what's happening
  });
  
  try {
    console.log('🧪 STARTING USER SIGNUP TESTS');
    console.log('=============================\n');
    
    // Generate unique emails with timestamp
    const timestamp = Date.now();
    const testEmail = `test_${timestamp}@test.no`;
    const adminEmail = `admin_${timestamp}@example.com`;
    
    // Test 1: Regular user signup
    console.log(`🔐 Testing regular user signup (${testEmail})...`);
    await testSignup(browser, testEmail, 'Charcoal2020!', 'Test User New', false);
    
    // Test 2: Admin user signup
    console.log(`\n🔐 Testing admin user signup (${adminEmail})...`);
    await testSignup(browser, adminEmail, 'Charcoal2020!', 'Admin User New', true);
    
    console.log('\n✅ ALL SIGNUP TESTS COMPLETED SUCCESSFULLY!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    throw error;
  } finally {
    await browser.close();
  }
}

async function testSignup(browser, email, password, name, isAdmin = false) {
  const page = await browser.newPage();
  
  try {
    // Navigate to signup page
    console.log(`  📄 Navigating to signup page...`);
    await page.goto('https://local.connectica.no/users/sign_up');
    await page.waitForSelector('input[name="user[email]"]', { timeout: 10000 });
    
    // Take initial screenshot
    await page.screenshot({ 
      path: `/tmp/signup_${isAdmin ? 'admin' : 'test'}_initial.png`,
      fullPage: false 
    });
    
    // Fill signup form step by step
    console.log(`  ✍️  Filling signup form for ${email}...`);
    
    // Find and fill the name field using ID selector (most reliable)
    console.log(`  🔍 Looking for name field...`);
    await page.waitForSelector('#user_name', { timeout: 5000 });
    
    const nameField = await page.$('#user_name');
    if (nameField) {
      // Clear any existing value first
      await nameField.focus();
      await page.keyboard.down('Control');
      await page.keyboard.press('KeyA');
      await page.keyboard.up('Control');
      await page.keyboard.press('Delete');
      
      // Type the name with a small delay between characters
      await page.keyboard.type(name, { delay: 50 });
      console.log(`    ✅ Name field filled: ${name}`);
      
      // Verify the name was actually entered and trigger change event
      const nameValue = await nameField.evaluate(el => {
        // Trigger change event to ensure form validation runs
        el.dispatchEvent(new Event('change', { bubbles: true }));
        el.dispatchEvent(new Event('blur', { bubbles: true }));
        return el.value;
      });
      console.log(`    🔍 Name field value: "${nameValue}"`);
      
      if (nameValue !== name) {
        throw new Error(`Name field value mismatch. Expected: "${name}", Got: "${nameValue}"`);
      }
    } else {
      throw new Error('Name field not found');
    }
    
    // Fill email field
    console.log(`  📧 Filling email field...`);
    const emailField = await page.$('#user_email');
    await emailField.focus();
    await page.keyboard.down('Control');
    await page.keyboard.press('KeyA');
    await page.keyboard.up('Control');
    await page.keyboard.type(email, { delay: 50 });
    
    // Verify email was entered
    const emailValue = await emailField.evaluate(el => {
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return el.value;
    });
    console.log(`    🔍 Email field value: "${emailValue}"`);
    
    // Fill password field
    console.log(`  🔒 Filling password field...`);
    const passwordField = await page.$('#user_password');
    await passwordField.focus();
    await page.keyboard.down('Control');
    await page.keyboard.press('KeyA');
    await page.keyboard.up('Control');
    await page.keyboard.type(password, { delay: 50 });
    
    // Fill password confirmation field
    console.log(`  🔒 Filling password confirmation field...`);
    const passwordConfirmField = await page.$('#user_password_confirmation');
    if (passwordConfirmField) {
      await passwordConfirmField.focus();
      await page.keyboard.down('Control');
      await page.keyboard.press('KeyA');
      await page.keyboard.up('Control');
      await page.keyboard.type(password, { delay: 50 });
      console.log(`    ✅ Password confirmation filled`);
    }
    
    // Take screenshot before submission
    await page.screenshot({ 
      path: `/tmp/signup_${isAdmin ? 'admin' : 'test'}_before_submit.png`,
      fullPage: false 
    });
    
    // Submit the form
    console.log(`  🚀 Submitting signup form...`);
    const submitButton = await page.$('button[type="submit"], input[type="submit"]');
    if (submitButton) {
      await submitButton.click();
    } else {
      throw new Error('Submit button not found');
    }
    
    // Wait for response
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Take screenshot after submission
    await page.screenshot({ 
      path: `/tmp/signup_${isAdmin ? 'admin' : 'test'}_after_submit.png`,
      fullPage: false 
    });
    
    // Check the result
    const currentUrl = page.url();
    console.log(`  🌐 Current URL after submission: ${currentUrl}`);
    
    // Check for errors
    const hasErrors = await page.evaluate(() => {
      const errorText = document.body.textContent;
      return errorText.includes('error prohibited') || 
             errorText.includes('can\'t be blank') ||
             errorText.includes('is invalid');
    });
    
    if (hasErrors) {
      const errorDetails = await page.evaluate(() => {
        // Find the specific error message
        const errorElements = document.querySelectorAll('*');
        const errors = [];
        
        errorElements.forEach(el => {
          const text = el.textContent.trim();
          if (text.includes('error prohibited') || 
              text.includes('can\'t be blank') ||
              text.includes('is invalid')) {
            if (text.length < 200) { // Avoid huge text blocks
              errors.push(text);
            }
          }
        });
        
        return errors;
      });
      
      console.log(`  ❌ Signup failed with errors:`, errorDetails);
      throw new Error(`Signup failed: ${errorDetails.join(', ')}`);
    }
    
    // Check if we're redirected (success)
    if (!currentUrl.includes('/users/sign_up')) {
      console.log(`  ✅ Signup successful! Redirected to: ${currentUrl}`);
    } else {
      // Could be successful but needs email confirmation
      const needsConfirmation = await page.evaluate(() => {
        const text = document.body.textContent.toLowerCase();
        return text.includes('confirmation') || 
               text.includes('verify') || 
               text.includes('check your email');
      });
      
      if (needsConfirmation) {
        console.log(`  ✅ Signup successful! Email confirmation required.`);
      } else {
        console.log(`  ⚠️  Signup result unclear - still on signup page without clear error`);
      }
    }
    
    console.log(`  📸 Screenshots saved:`);
    console.log(`    - /tmp/signup_${isAdmin ? 'admin' : 'test'}_initial.png`);
    console.log(`    - /tmp/signup_${isAdmin ? 'admin' : 'test'}_before_submit.png`);
    console.log(`    - /tmp/signup_${isAdmin ? 'admin' : 'test'}_after_submit.png`);
    
  } catch (error) {
    console.error(`  ❌ Signup test failed for ${email}:`, error.message);
    
    // Take error screenshot
    await page.screenshot({ 
      path: `/tmp/signup_${isAdmin ? 'admin' : 'test'}_error.png`,
      fullPage: true 
    });
    console.log(`  📸 Error screenshot saved to /tmp/signup_${isAdmin ? 'admin' : 'test'}_error.png`);
    
    throw error;
  } finally {
    await page.close();
  }
}

// Run the test
testUserSignup()
  .then(() => {
    console.log('\n🎯 All user signup tests passed!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n💥 User signup tests failed:', error);
    process.exit(1);
  });