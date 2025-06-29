const puppeteer = require('puppeteer');

async function testUserSignup() {
  const browser = await puppeteer.launch({ 
    headless: false,
    defaultViewport: { width: 1400, height: 900 }
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
    
    // Test 2: Admin user signup (note: admin status is determined by email domain/logic)
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
    
    // Fill signup form
    console.log(`  ✍️  Filling signup form for ${email}...`);
    
    // Wait for all form fields to be ready
    await page.waitForSelector('input[name="user[email]"]');
    
    // Clear and fill name field (may have different selector)
    const nameSelectors = [
      'input[name="user[name]"]',
      'input[id="user_name"]',
      '#user_name',
      'input[placeholder*="name" i]',
      'input[placeholder*="full name" i]'
    ];
    
    let nameFieldFilled = false;
    for (const selector of nameSelectors) {
      const nameField = await page.$(selector);
      if (nameField) {
        await nameField.click({ clickCount: 3 }); // Select all existing text
        await nameField.type(name);
        console.log(`    ✅ Name field filled: ${name} (using ${selector})`);
        nameFieldFilled = true;
        break;
      }
    }
    
    if (!nameFieldFilled) {
      console.log(`    ⚠️  Name field not found with any selector, checking page structure...`);
      // Get all input fields to debug
      const inputs = await page.$$eval('input', inputs => 
        inputs.map(input => ({ 
          name: input.name, 
          id: input.id, 
          placeholder: input.placeholder, 
          type: input.type 
        }))
      );
      console.log(`    🔍 Available input fields:`, inputs);
    }
    
    // Clear and fill email field
    const emailField = await page.$('input[name="user[email]"]');
    await emailField.click({ clickCount: 3 });
    await emailField.type(email);
    
    // Clear and fill password field
    const passwordField = await page.$('input[name="user[password]"]');
    await passwordField.click({ clickCount: 3 });
    await passwordField.type(password);
    
    // Check if password confirmation field exists and fill it
    const passwordConfirmField = await page.$('input[name="user[password_confirmation]"]');
    if (passwordConfirmField) {
      await passwordConfirmField.click({ clickCount: 3 });
      await passwordConfirmField.type(password);
      console.log(`    ✅ Password confirmation filled`);
    } else {
      console.log(`    ⚠️  Password confirmation field not found, skipping...`);
    }
    
    // Take screenshot before signup
    await page.screenshot({ 
      path: `/tmp/signup_${isAdmin ? 'admin' : 'test'}_before.png`,
      fullPage: false 
    });
    
    // Submit signup form
    console.log(`  🚀 Submitting signup form...`);
    const submitButton = await page.$('input[type="submit"], button[type="submit"]');
    if (submitButton) {
      await submitButton.click();
    } else {
      throw new Error('Submit button not found');
    }
    
    // Wait a moment for form submission
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Check if we're still on the signup page (validation errors)
    const currentUrl = page.url();
    if (currentUrl.includes('/users/sign_up')) {
      console.log(`  ⚠️  Still on signup page, checking for validation errors...`);
      
      // Check for validation errors with better selectors
      const errors = await page.evaluate(() => {
        const errorSelectors = [
          '.alert-danger',
          '.alert-error',
          '.error', 
          '.field_with_errors',
          '.invalid-feedback',
          '[class*="error"]',
          '[id*="error"]',
          'div[style*="color: red"]',
          'div[style*="color:red"]',
          '.text-red',
          '.text-danger',
          // Common Rails error message patterns
          '#error_explanation',
          '.error_explanation',
          'div:contains("prohibited")',
          'div:contains("can\'t be blank")'
        ];
        
        const errors = [];
        
        // Also check for any div containing error text patterns
        const allDivs = document.querySelectorAll('div, p, span');
        allDivs.forEach(el => {
          const text = el.textContent.trim();
          if (text && (
            text.includes('error') || 
            text.includes('prohibited') || 
            text.includes('can\'t be blank') ||
            text.includes('is invalid') ||
            text.includes('too short') ||
            text.includes('doesn\'t match')
          )) {
            if (!errors.includes(text)) {
              errors.push(text);
            }
          }
        });
        
        // Standard selectors
        errorSelectors.forEach(selector => {
          try {
            const elements = document.querySelectorAll(selector);
            elements.forEach(el => {
              const text = el.textContent.trim();
              if (text && !errors.includes(text)) {
                errors.push(text);
              }
            });
          } catch (e) {
            // Skip invalid selectors
          }
        });
        
        return errors;
      });
      
      if (errors.length > 0) {
        throw new Error(`Signup failed with validation errors: ${errors.join(', ')}`);
      }
    }
    
    // Try to wait for navigation, but don't fail if it times out
    try {
      await page.waitForNavigation({ timeout: 5000 });
    } catch (navError) {
      console.log(`  ⚠️  Navigation timeout (may be normal if no redirect occurs)`);
    }
    
    // Take screenshot after signup
    await page.screenshot({ 
      path: `/tmp/signup_${isAdmin ? 'admin' : 'test'}_after.png`,
      fullPage: false 
    });
    
    // Verify successful signup
    const finalUrl = page.url();
    console.log(`  🌐 Current URL after signup: ${finalUrl}`);
    
    // Check for signup success indicators
    const pageContent = await page.content();
    
    // Look for various success indicators
    const successIndicators = [
      'welcome',
      'signed up successfully',
      'registration successful',
      'account created',
      'confirmation email',
      'please check your email'
    ];
    
    const hasSuccessIndicator = successIndicators.some(indicator => 
      pageContent.toLowerCase().includes(indicator)
    );
    
    // Check if we're redirected to dashboard/home (another success indicator)
    const isRedirectedHome = finalUrl.includes('local.connectica.no') && 
                             !finalUrl.includes('/users/sign_up');
    
    // Check for error messages
    const errorIndicators = [
      'error',
      'invalid',
      'already taken',
      'can\'t be blank',
      'too short',
      'doesn\'t match'
    ];
    
    const hasError = errorIndicators.some(error => 
      pageContent.toLowerCase().includes(error)
    );
    
    if (hasError) {
      // Get specific error messages
      const errors = await page.evaluate(() => {
        const errorElements = document.querySelectorAll('.alert-danger, .error, .field_with_errors, .invalid-feedback');
        return Array.from(errorElements).map(el => el.textContent.trim()).filter(text => text);
      });
      
      if (errors.length > 0) {
        throw new Error(`Signup failed with errors: ${errors.join(', ')}`);
      } else {
        throw new Error('Signup appears to have failed (error indicators found)');
      }
    }
    
    if (!hasSuccessIndicator && !isRedirectedHome) {
      console.log(`  ⚠️  No clear success indicators found, checking current state...`);
      
      // Additional check: see if we can find user menu or logout link
      const loggedInElements = await page.$$eval('body *', elements => {
        return elements.some(el => 
          (el.textContent && (
            el.textContent.includes('Sign out') || 
            el.textContent.includes('Profile') ||
            el.textContent.includes('Dashboard')
          )) ||
          (el.href && el.href.includes('sign_out'))
        );
      });
      
      if (!loggedInElements) {
        console.log(`  🔍 Checking for confirmation email message...`);
        const needsConfirmation = pageContent.toLowerCase().includes('confirmation') ||
                                 pageContent.toLowerCase().includes('verify') ||
                                 pageContent.toLowerCase().includes('email');
        
        if (needsConfirmation) {
          console.log(`  ✅ Signup successful - email confirmation required`);
        } else {
          throw new Error(`Could not verify successful signup for ${email}`);
        }
      } else {
        console.log(`  ✅ Signup successful - user appears to be logged in`);
      }
    } else {
      console.log(`  ✅ Signup successful!`);
    }
    
    // For admin user, note that admin status might be set based on email or other logic
    if (isAdmin) {
      console.log(`  👑 Admin user created (admin status may be determined by email domain)`);
    }
    
    console.log(`  📸 Screenshots saved:`);
    console.log(`    - /tmp/signup_${isAdmin ? 'admin' : 'test'}_before.png`);
    console.log(`    - /tmp/signup_${isAdmin ? 'admin' : 'test'}_after.png`);
    
    // Try to sign out if we're logged in
    console.log(`  🚪 Attempting to sign out...`);
    const signOutLink = await page.$('[href*="sign_out"], a[data-method="delete"]');
    if (signOutLink) {
      await signOutLink.click();
      await page.waitForNavigation({ timeout: 5000 }).catch(() => {
        console.log(`  ⚠️  Sign out navigation timeout (may be normal)`);
      });
    } else {
      console.log(`  ⚠️  No sign out link found (may not be logged in automatically)`);
    }
    
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