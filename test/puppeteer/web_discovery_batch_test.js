const puppeteer = require('puppeteer');

async function testWebDiscoveryBatchSize() {
  const browser = await puppeteer.launch({ 
    headless: false,
    devtools: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
    defaultViewport: { width: 1200, height: 800 }
  });
  
  try {
    const page = await browser.newPage();
    
    // Enable console logging from the page
    page.on('console', msg => {
      console.log('🖥️  PAGE:', msg.text());
    });
    
    // Log network requests
    page.on('request', request => {
      if (request.url().includes('queue_web_discovery')) {
        console.log('📤 REQUEST:', request.method(), request.url());
        console.log('📤 POST DATA:', request.postData());
      }
    });
    
    page.on('response', async response => {
      if (response.url().includes('queue_web_discovery')) {
        console.log('📥 RESPONSE:', response.status(), response.url());
        try {
          const responseText = await response.text();
          console.log('📥 RESPONSE BODY:', responseText);
        } catch (e) {
          console.log('📥 Could not read response body');
        }
      }
    });
    
    console.log('🌐 Navigating to login page...');
    await page.goto('https://local.connectica.no/users/sign_in', { 
      waitUntil: 'networkidle0',
      timeout: 30000 
    });
    
    console.log('🔐 Attempting login...');
    
    // Wait for the email/password form to load (not the OAuth buttons)
    await page.waitForSelector('form input[type="email"]', { timeout: 10000 });
    
    // Specifically target the email/password form, not any OAuth forms
    const emailInput = await page.$('form input[type="email"]');
    const passwordInput = await page.$('form input[type="password"]');
    
    if (!emailInput || !passwordInput) {
      throw new Error('Could not find email/password form inputs');
    }
    
    // Clear and type credentials
    await emailInput.click({ clickCount: 3 }); // Select all
    await emailInput.type('test@test.no');
    
    await passwordInput.click({ clickCount: 3 }); // Select all  
    await passwordInput.type('CodemyFTW2');
    
    // Take screenshot before login
    await page.screenshot({ path: '/tmp/before_login.png' });
    console.log('📸 Screenshot saved: /tmp/before_login.png');
    
    // Find the specific submit button for the email/password form (not OAuth)
    // Look for the blue "Sign in" button within the same form as the email input
    const submitButton = await page.evaluateHandle(() => {
      const emailInput = document.querySelector('form input[type="email"]');
      if (!emailInput) return null;
      
      const form = emailInput.closest('form');
      if (!form) return null;
      
      // Find submit button within this specific form
      return form.querySelector('input[type="submit"], button[type="submit"]');
    });
    
    if (!submitButton.asElement()) {
      throw new Error('Could not find submit button for email/password form');
    }
    
    console.log('🚀 Clicking email/password form submit button...');
    
    // Submit the email/password form specifically
    await Promise.all([
      page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 15000 }),
      submitButton.asElement().click()
    ]);
    
    // Check if we're still on login page
    const currentUrl = page.url();
    console.log('🌐 Current URL after login:', currentUrl);
    
    if (currentUrl.includes('sign_in')) {
      console.log('⚠️  Still on login page, trying admin credentials...');
      
      // Clear fields and try admin
      await page.evaluate(() => {
        document.querySelector('input[type="email"]').value = '';
        document.querySelector('input[type="password"]').value = '';
      });
      
      await page.type('input[type="email"]', 'admin@example.com');
      await page.type('input[type="password"]', 'CodemyFTW2');
      
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 15000 }),
        page.click('button[type="submit"]')
      ]);
      
      const newUrl = page.url();
      console.log('🌐 URL after admin login attempt:', newUrl);
      
      if (newUrl.includes('sign_in')) {
        throw new Error('❌ Login failed with both test and admin credentials');
      }
    }
    
    console.log('✅ Login successful! Navigating to companies page...');
    
    // Navigate to companies page
    await page.goto('https://local.connectica.no/companies', { 
      waitUntil: 'networkidle0',
      timeout: 30000 
    });
    
    // Wait for the page to load and find Web Discovery form
    console.log('🔍 Looking for Web Discovery form...');
    await page.waitForSelector('[data-service="company_web_discovery"]', { timeout: 15000 });
    
    // Take screenshot of companies page
    await page.screenshot({ path: '/tmp/companies_page.png' });
    console.log('📸 Screenshot saved: /tmp/companies_page.png');
    
    // Find the count input field for Web Discovery
    const countInputSelector = '[data-service="company_web_discovery"] input[name="count"]';
    await page.waitForSelector(countInputSelector, { timeout: 10000 });
    
    // Get current value
    const currentValue = await page.$eval(countInputSelector, input => input.value);
    console.log('📊 Current batch size value:', currentValue);
    
    // Clear and set to 5
    console.log('✏️  Setting batch size to 5...');
    await page.$eval(countInputSelector, input => {
      input.focus();
      input.select();
      input.value = '5';
      // Trigger change event
      input.dispatchEvent(new Event('change', { bubbles: true }));
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    
    // Verify the value was set
    const newValue = await page.$eval(countInputSelector, input => input.value);
    console.log('✅ New batch size value:', newValue);
    
    // Take screenshot before submission
    await page.screenshot({ path: '/tmp/before_submit.png' });
    console.log('📸 Screenshot saved: /tmp/before_submit.png');
    
    // Find and click the submit button
    const submitButtonSelector = '[data-service="company_web_discovery"] button[type="submit"]';
    await page.waitForSelector(submitButtonSelector, { timeout: 10000 });
    
    console.log('🚀 Submitting form with batch size 5...');
    
    // Click submit and wait for the response
    await page.click(submitButtonSelector);
    
    // Wait a bit for the request to complete
    await page.waitForTimeout(5000);
    
    // Take screenshot after submission
    await page.screenshot({ path: '/tmp/after_submit.png' });
    console.log('📸 Screenshot saved: /tmp/after_submit.png');
    
    console.log('✅ Test completed! Check the console output above for request/response details.');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    
    // Take error screenshot
    try {
      const page = browser.defaultBrowserContext().pages()[0];
      if (page) {
        await page.screenshot({ path: '/tmp/error_screenshot.png' });
        console.log('📸 Error screenshot saved: /tmp/error_screenshot.png');
      }
    } catch (screenshotError) {
      console.log('Could not take error screenshot');
    }
    
    throw error;
  } finally {
    // Keep browser open for manual inspection
    console.log('🔍 Browser will remain open for 10 seconds for inspection...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    await browser.close();
  }
}

// Run the test
if (require.main === module) {
  testWebDiscoveryBatchSize().catch(console.error);
}

module.exports = testWebDiscoveryBatchSize;