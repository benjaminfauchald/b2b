const puppeteer = require('puppeteer');

describe('Domain Testing UI', () => {
  let browser;
  let page;
  const baseUrl = 'https://local.connectica.no';
  
  beforeAll(async () => {
    browser = await puppeteer.launch({
      headless: false, // Set to true for CI
      slowMo: 50, // Slow down by 50ms to see what's happening
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
  });

  afterAll(async () => {
    await browser.close();
  });

  beforeEach(async () => {
    page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 800 });
    
    // Login first (assuming you have a login page)
    await page.goto(`${baseUrl}/users/sign_in`);
    await page.type('#user_email', 'test@example.com');
    await page.type('#user_password', 'password123');
    await page.click('input[type="submit"]');
    await page.waitForNavigation();
  });

  afterEach(async () => {
    await page.close();
  });

  test('DNS testing button provides proper feedback', async () => {
    // Navigate to a domain detail page
    await page.goto(`${baseUrl}/domains/1`);
    await page.waitForSelector('[data-service="dns"]');

    // Take initial screenshot
    await page.screenshot({ path: 'screenshots/domain-initial.png' });

    // Find the DNS testing section
    const dnsSection = await page.$('[data-service="dns"]');
    
    // Verify initial state
    const initialStatus = await dnsSection.$eval('[data-status-target="status"]', el => el.textContent.trim());
    expect(initialStatus).toBe('Not Tested');
    
    const initialLastTested = await dnsSection.$eval('.text-xs.text-gray-500', el => el.textContent.trim());
    expect(initialLastTested).toBe('Never tested');
    
    // Check button state
    const button = await dnsSection.$('button[type="submit"]');
    const isDisabled = await button.evaluate(el => el.disabled);
    expect(isDisabled).toBe(false);
    
    const buttonText = await button.evaluate(el => el.textContent.trim());
    expect(buttonText).toContain('Test DNS');

    // Click the Test DNS button
    await button.click();

    // Wait a moment for the UI to update
    await page.waitForTimeout(100);

    // Take screenshot of loading state
    await page.screenshot({ path: 'screenshots/domain-testing.png' });

    // Verify button becomes disabled and shows "Testing..."
    const isDisabledAfterClick = await button.evaluate(el => el.disabled);
    expect(isDisabledAfterClick).toBe(true);
    
    const buttonTextAfterClick = await button.evaluate(el => el.textContent.trim());
    expect(buttonTextAfterClick).toContain('Testing...');

    // Verify status badge updates to "Testing..."
    await page.waitForFunction(
      () => {
        const statusEl = document.querySelector('[data-service="dns"] [data-status-target="status"]');
        return statusEl && statusEl.textContent.includes('Testing...');
      },
      { timeout: 5000 }
    );

    // Wait for toast notification
    await page.waitForSelector('.bg-green-500', { timeout: 5000 });
    const toastText = await page.$eval('.bg-green-500', el => el.textContent.trim());
    expect(toastText).toContain('queued');

    // Take screenshot with toast
    await page.screenshot({ path: 'screenshots/domain-toast.png' });

    // Wait for the test to complete (in real scenario, this would take longer)
    await page.waitForTimeout(6000); // Wait for polling to update the UI

    // Reload the page to see the final state
    await page.reload();
    await page.waitForSelector('[data-service="dns"]');

    // Take final screenshot
    await page.screenshot({ path: 'screenshots/domain-completed.png' });

    // Verify final state
    const finalDnsSection = await page.$('[data-service="dns"]');
    const finalStatus = await finalDnsSection.$eval('[data-status-target="status"]', el => el.textContent.trim());
    expect(['Active', 'Inactive']).toContain(finalStatus);

    const finalLastTested = await finalDnsSection.$eval('.text-xs.text-gray-500', el => el.textContent.trim());
    expect(finalLastTested).toContain('ago');

    const finalButton = await finalDnsSection.$('button[type="submit"]');
    const finalButtonText = await finalButton.evaluate(el => el.textContent.trim());
    expect(finalButtonText).toMatch(/Re-test DNS|Retry DNS/);
  });

  test('Multiple services can be tested independently', async () => {
    await page.goto(`${baseUrl}/domains/1`);
    await page.waitForSelector('[data-service="dns"]');

    // Click DNS test
    const dnsButton = await page.$('[data-service="dns"] button[type="submit"]');
    await dnsButton.click();

    // Verify DNS is testing
    const dnsButtonText = await dnsButton.evaluate(el => el.textContent.trim());
    expect(dnsButtonText).toContain('Testing...');

    // Click MX test while DNS is still testing
    const mxButton = await page.$('[data-service="mx"] button[type="submit"]');
    const mxButtonDisabled = await mxButton.evaluate(el => el.disabled);
    expect(mxButtonDisabled).toBe(false); // Should still be clickable

    await mxButton.click();

    // Verify both are testing
    const mxButtonText = await mxButton.evaluate(el => el.textContent.trim());
    expect(mxButtonText).toContain('Testing...');

    // Take screenshot of both testing
    await page.screenshot({ path: 'screenshots/domain-multiple-testing.png' });
  });

  test('Service disabled state is properly shown', async () => {
    // This would require setting up a domain with disabled service
    // For now, we'll check if disabled buttons have proper styling
    await page.goto(`${baseUrl}/domains/1`);
    await page.waitForSelector('[data-service="dns"]');

    // Check if any buttons are disabled
    const disabledButtons = await page.$$('button[disabled]');
    for (const button of disabledButtons) {
      const classList = await button.evaluate(el => el.className);
      expect(classList).toContain('cursor-not-allowed');
      expect(classList).toContain('bg-gray-300');
    }
  });

  test('Real-time polling updates the UI', async () => {
    await page.goto(`${baseUrl}/domains/1`);
    await page.waitForSelector('[data-service="dns"]');

    // Start DNS test
    const dnsButton = await page.$('[data-service="dns"] button[type="submit"]');
    await dnsButton.click();

    // Monitor for status changes without page reload
    let statusChanged = false;
    
    // Set up a listener for DOM changes
    await page.evaluateOnNewDocument(() => {
      window.statusChanges = [];
      const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.target.matches && mutation.target.matches('[data-status-target="status"]')) {
            window.statusChanges.push({
              time: new Date().toISOString(),
              text: mutation.target.textContent.trim()
            });
          }
        });
      });
      
      // Start observing when the page loads
      setTimeout(() => {
        const statusElement = document.querySelector('[data-service="dns"] [data-status-target="status"]');
        if (statusElement) {
          observer.observe(statusElement, { 
            childList: true, 
            characterData: true, 
            subtree: true 
          });
        }
      }, 1000);
    });

    // Wait for potential status updates
    await page.waitForTimeout(10000); // Wait 10 seconds for polling

    // Check if status changed
    const changes = await page.evaluate(() => window.statusChanges || []);
    console.log('Status changes detected:', changes);

    // Take final screenshot
    await page.screenshot({ path: 'screenshots/domain-after-polling.png' });
  });
});

// Helper function to run a single test
async function runTest(testName) {
  const test = global[testName];
  if (test) {
    console.log(`Running test: ${testName}`);
    try {
      await test();
      console.log(`✓ ${testName} passed`);
    } catch (error) {
      console.error(`✗ ${testName} failed:`, error);
    }
  }
}

// If running directly (not through Jest)
if (require.main === module) {
  (async () => {
    console.log('Running Puppeteer tests for Domain Testing UI...\n');
    
    // You would need to implement the test runner logic here
    // For now, this is a placeholder
    console.log('Please run with Jest: npm test domain_testing_ui.test.js');
  })();
}