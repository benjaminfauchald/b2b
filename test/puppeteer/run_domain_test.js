const puppeteer = require('puppeteer');

// Simple test runner for domain testing UI
async function runDomainTestingUITest() {
  console.log('🧪 Running Domain Testing UI Test with Puppeteer...\n');
  
  let browser;
  try {
    // Launch browser
    browser = await puppeteer.launch({
      headless: false, // Set to true for CI
      slowMo: 100, // Slow down to see what's happening
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
      devtools: true
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 800 });

    // Enable console logging
    page.on('console', msg => console.log('Browser console:', msg.text()));
    page.on('pageerror', error => console.log('Page error:', error.message));

    console.log('1️⃣ Navigating to login page...');
    await page.goto('https://local.connectica.no/users/sign_in', { waitUntil: 'networkidle0' });
    
    // Take screenshot of login page
    await page.screenshot({ path: 'test/puppeteer/screenshots/01-login.png' });

    // Login with test user
    console.log('2️⃣ Logging in...');
    await page.type('#user_email', 'test@test.no');
    await page.type('#user_password', 'CodemyFTW2');
    await page.click('input[type="submit"]');
    
    // Wait for navigation after login
    await page.waitForNavigation({ waitUntil: 'networkidle0' });
    await page.screenshot({ path: 'test/puppeteer/screenshots/02-after-login.png' });

    console.log('3️⃣ Navigating to domains page...');
    await page.goto('https://local.connectica.no/domains', { waitUntil: 'networkidle0' });
    await page.screenshot({ path: 'test/puppeteer/screenshots/03-domains-list.png' });

    // Click on the first domain in the list
    console.log('4️⃣ Clicking on first domain...');
    const firstDomainLink = await page.$('table tbody tr:first-child a');
    if (firstDomainLink) {
      await firstDomainLink.click();
      await page.waitForNavigation({ waitUntil: 'networkidle0' });
    } else {
      throw new Error('No domains found in the list');
    }
    
    await page.screenshot({ path: 'test/puppeteer/screenshots/04-domain-detail.png' });

    // Wait for the DNS testing section
    console.log('5️⃣ Finding DNS testing section...');
    await page.waitForSelector('[data-service="dns"]', { timeout: 10000 });

    // Get initial state
    const dnsSection = await page.$('[data-service="dns"]');
    const initialStatus = await page.evaluate(
      el => el.querySelector('[data-status-target="status"]')?.textContent.trim(),
      dnsSection
    );
    console.log(`   Initial DNS status: ${initialStatus}`);

    const initialLastTested = await page.evaluate(
      el => el.querySelector('.text-xs.text-gray-500')?.textContent.trim(),
      dnsSection
    );
    console.log(`   Last tested: ${initialLastTested}`);

    // Find and check the button
    console.log('6️⃣ Checking DNS test button...');
    const button = await dnsSection.$('button[type="submit"]');
    const buttonInfo = await page.evaluate(el => ({
      text: el.textContent.trim(),
      disabled: el.disabled,
      className: el.className
    }), button);
    console.log(`   Button text: "${buttonInfo.text}"`);
    console.log(`   Button disabled: ${buttonInfo.disabled}`);

    // Click the Test DNS button
    console.log('7️⃣ Clicking Test DNS button...');
    await button.click();
    
    // Wait a moment for UI to update
    await page.waitForTimeout(500);
    await page.screenshot({ path: 'test/puppeteer/screenshots/05-after-click.png' });

    // Check button state after click
    const buttonAfterClick = await page.evaluate(el => ({
      text: el.textContent.trim(),
      disabled: el.disabled,
      className: el.className
    }), button);
    console.log(`   Button after click: "${buttonAfterClick.text}"`);
    console.log(`   Button disabled: ${buttonAfterClick.disabled}`);

    // Check for status update
    const statusAfterClick = await page.evaluate(
      el => el.querySelector('[data-status-target="status"]')?.textContent.trim(),
      dnsSection
    );
    console.log(`   Status after click: ${statusAfterClick}`);

    // Wait for toast notification
    console.log('8️⃣ Waiting for toast notification...');
    try {
      await page.waitForSelector('.fixed.top-4.right-4', { timeout: 5000 });
      const toastText = await page.$eval('.fixed.top-4.right-4', el => el.textContent.trim());
      console.log(`   Toast message: "${toastText}"`);
      await page.screenshot({ path: 'test/puppeteer/screenshots/06-toast.png' });
    } catch (e) {
      console.log('   No toast notification found');
    }

    // Wait for status to potentially update via polling
    console.log('9️⃣ Waiting for status updates (10 seconds)...');
    await page.waitForTimeout(10000);
    
    // Check final status
    const finalStatus = await page.evaluate(
      el => el.querySelector('[data-status-target="status"]')?.textContent.trim(),
      dnsSection
    );
    console.log(`   Final status: ${finalStatus}`);
    await page.screenshot({ path: 'test/puppeteer/screenshots/07-final-state.png' });

    // Test multiple services
    console.log('\n🔟 Testing multiple services simultaneously...');
    
    // Test MX while DNS might still be running
    const mxSection = await page.$('[data-service="mx"]');
    if (mxSection) {
      const mxButton = await mxSection.$('button[type="submit"]');
      const mxButtonInfo = await page.evaluate(el => ({
        text: el.textContent.trim(),
        disabled: el.disabled
      }), mxButton);
      console.log(`   MX button: "${mxButtonInfo.text}", disabled: ${mxButtonInfo.disabled}`);
      
      if (!mxButtonInfo.disabled) {
        await mxButton.click();
        console.log('   Clicked MX test button');
        await page.waitForTimeout(500);
        await page.screenshot({ path: 'test/puppeteer/screenshots/08-multiple-tests.png' });
      }
    }

    console.log('\n✅ Test completed successfully!');
    console.log('📸 Screenshots saved in test/puppeteer/screenshots/');

  } catch (error) {
    console.error('\n❌ Test failed:', error);
    await page.screenshot({ path: 'test/puppeteer/screenshots/error.png' });
    throw error;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

// Create screenshots directory
const fs = require('fs');
const path = require('path');
const screenshotsDir = path.join(__dirname, 'screenshots');
if (!fs.existsSync(screenshotsDir)) {
  fs.mkdirSync(screenshotsDir, { recursive: true });
}

// Run the test
runDomainTestingUITest().catch(console.error);