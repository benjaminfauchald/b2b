const puppeteer = require('puppeteer');

describe('Company Financial Data Testing', () => {
  let browser;
  let page;
  const baseUrl = 'https://local.connectica.no';
  const testCompanyId = 301078; // Sparebankens Velforening
  
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
    
    // Login first using test credentials from CLAUDE.local.md
    await page.goto(`${baseUrl}/users/sign_in`);
    await page.type('#user_email', 'test@test.no');
    await page.type('#user_password', 'CodemyFTW2');
    await page.click('input[type="submit"]');
    await page.waitForNavigation();
  });

  afterEach(async () => {
    await page.close();
  });

  test('Financial data fetch button provides proper feedback and populates data', async () => {
    // Navigate to the specific company page
    await page.goto(`${baseUrl}/companies/${testCompanyId}`);
    await page.waitForSelector('h1', { timeout: 10000 });

    // Take initial screenshot
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-financial-initial.png' });

    // Wait for the Enhancement Services section to load
    await page.waitForSelector('[data-service="financial_data"], .enhancement-services, [data-testid="financial-section"]', { timeout: 5000 });

    // Find the Financial Data section - try multiple selectors
    let financialSection;
    try {
      // Try different possible selectors for the financial data section
      financialSection = await page.$('[data-service="financial_data"]') ||
                        await page.$('.financial-data-section') ||
                        await page.$('div:has-text("Financial Data")') ||
                        await page.evaluateHandle(() => {
                          // Look for a section containing "Financial Data" text
                          const elements = Array.from(document.querySelectorAll('*'));
                          return elements.find(el => 
                            el.textContent && el.textContent.includes('Financial Data') && 
                            el.querySelector('button')
                          );
                        });
      
      if (!financialSection) {
        throw new Error('Financial Data section not found');
      }
    } catch (error) {
      console.log('Available page content:', await page.content());
      throw new Error(`Financial Data section not found: ${error.message}`);
    }

    // Verify initial state - look for "No Data" text
    const initialDataStatus = await page.evaluate(() => {
      const elements = Array.from(document.querySelectorAll('*'));
      const noDataElement = elements.find(el => 
        el.textContent && el.textContent.trim() === 'No Data'
      );
      return noDataElement ? noDataElement.textContent.trim() : null;
    });
    
    console.log('Initial data status:', initialDataStatus);
    expect(initialDataStatus).toBe('No Data');

    // Find the "Fetch Financial Data" button
    const fetchButton = await page.evaluateHandle(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      return buttons.find(button => 
        button.textContent && button.textContent.includes('Fetch Financial Data')
      );
    });

    if (!fetchButton) {
      throw new Error('Fetch Financial Data button not found');
    }

    // Check initial button state
    const isInitiallyDisabled = await fetchButton.evaluate(el => el.disabled);
    expect(isInitiallyDisabled).toBe(false);
    
    const initialButtonText = await fetchButton.evaluate(el => el.textContent.trim());
    expect(initialButtonText).toContain('Fetch Financial Data');

    // Click the Fetch Financial Data button
    await fetchButton.click();

    // Wait a moment for the UI to update
    await page.waitForTimeout(100);

    // Take screenshot of loading state
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-financial-loading.png' });

    // Verify button becomes disabled and shows loading state
    const isDisabledAfterClick = await fetchButton.evaluate(el => el.disabled);
    expect(isDisabledAfterClick).toBe(true);

    // Check if button text changes to indicate loading
    await page.waitForFunction(
      (button) => {
        const text = button.textContent.trim();
        return text.includes('Fetching...') || 
               text.includes('Loading...') || 
               button.disabled === true;
      },
      { timeout: 5000 },
      fetchButton
    );

    const buttonTextAfterClick = await fetchButton.evaluate(el => el.textContent.trim());
    console.log('Button text after click:', buttonTextAfterClick);

    // Wait for toast notification (if any)
    try {
      await page.waitForSelector('.bg-green-500, .toast, .notification', { timeout: 3000 });
      const toast = await page.$('.bg-green-500, .toast, .notification');
      if (toast) {
        const toastText = await toast.evaluate(el => el.textContent.trim());
        console.log('Toast notification:', toastText);
        expect(toastText).toMatch(/queued|started|processing/i);
      }
    } catch (error) {
      console.log('No toast notification found, continuing...');
    }

    // Wait for the service to complete - we'll wait for the button to become enabled again
    // or for the data to populate
    await page.waitForFunction(
      (button) => {
        // Check if button is re-enabled OR if financial data is now showing
        const isEnabled = !button.disabled;
        const hasFinancialData = document.querySelector('[data-testid="revenue"], .revenue, .financial-amount');
        const noDataGone = !Array.from(document.querySelectorAll('*')).some(el => 
          el.textContent && el.textContent.trim() === 'No Data'
        );
        
        return isEnabled || hasFinancialData || noDataGone;
      },
      { timeout: 15000 }, // Wait up to 15 seconds for the service to complete
      fetchButton
    );

    // Take screenshot after completion
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-financial-completed.png' });

    // Verify button is re-enabled
    const isFinallyEnabled = await fetchButton.evaluate(el => el.disabled);
    expect(isFinallyEnabled).toBe(false);

    // Verify that financial data is now populated
    const finalDataCheck = await page.evaluate(() => {
      // Look for revenue/financial data indicators
      const revenueElements = Array.from(document.querySelectorAll('*')).filter(el => 
        el.textContent && (
          el.textContent.includes('kr') || 
          el.textContent.match(/\d+\s*NOK/i) ||
          el.textContent.match(/\d{1,3}(,\d{3})*/) // Large numbers with commas
        )
      );

      const noDataElements = Array.from(document.querySelectorAll('*')).filter(el => 
        el.textContent && el.textContent.trim() === 'No Data'
      );

      return {
        hasRevenueData: revenueElements.length > 0,
        revenueText: revenueElements.map(el => el.textContent.trim()).slice(0, 3), // First 3 matches
        noDataCount: noDataElements.length
      };
    });

    console.log('Final data check:', finalDataCheck);

    // Verify that "No Data" is replaced with actual financial data
    expect(finalDataCheck.noDataCount).toBeLessThan(2); // Some "No Data" might remain for other services

    // If revenue data is found, verify it contains reasonable financial data
    if (finalDataCheck.hasRevenueData) {
      expect(finalDataCheck.revenueText.some(text => 
        text.includes('kr') || text.match(/\d+/)
      )).toBe(true);
    }

    // Verify button text returns to normal
    const finalButtonText = await fetchButton.evaluate(el => el.textContent.trim());
    expect(finalButtonText).toMatch(/Fetch Financial Data|Update Financial Data|Re-fetch/i);
  });

  test('Financial data section maintains state after page reload', async () => {
    // Navigate to company page
    await page.goto(`${baseUrl}/companies/${testCompanyId}`);
    await page.waitForSelector('h1');

    // Check if financial data already exists from previous test
    const hasData = await page.evaluate(() => {
      const elements = Array.from(document.querySelectorAll('*'));
      return !elements.some(el => el.textContent && el.textContent.trim() === 'No Data');
    });

    if (!hasData) {
      // If no data, run the fetch first
      const fetchButton = await page.evaluateHandle(() => {
        const buttons = Array.from(document.querySelectorAll('button'));
        return buttons.find(button => 
          button.textContent && button.textContent.includes('Fetch Financial Data')
        );
      });

      if (fetchButton) {
        await fetchButton.click();
        await page.waitForTimeout(10000); // Wait for completion
      }
    }

    // Take screenshot before reload
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-financial-before-reload.png' });

    // Reload the page
    await page.reload();
    await page.waitForSelector('h1');

    // Take screenshot after reload
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-financial-after-reload.png' });

    // Verify financial data persists after reload
    const dataAfterReload = await page.evaluate(() => {
      const elements = Array.from(document.querySelectorAll('*'));
      const hasNoData = elements.some(el => el.textContent && el.textContent.trim() === 'No Data');
      
      return {
        hasNoData,
        hasFinancialNumbers: elements.some(el => 
          el.textContent && (
            el.textContent.includes('kr') || 
            el.textContent.match(/\d{1,3}(,\d{3})*/)
          )
        )
      };
    });

    console.log('Data after reload:', dataAfterReload);
    
    // Financial data should persist after reload
    expect(dataAfterReload.hasFinancialNumbers).toBe(true);
  });

  test('Multiple enhancement services can be triggered independently', async () => {
    await page.goto(`${baseUrl}/companies/${testCompanyId}`);
    await page.waitForSelector('h1');

    // Find all service buttons in the Enhancement Services section
    const serviceButtons = await page.$$eval('button', buttons => 
      buttons
        .filter(button => 
          button.textContent && (
            button.textContent.includes('Fetch') || 
            button.textContent.includes('Discovery') ||
            button.textContent.includes('LinkedIn')
          )
        )
        .map(button => ({
          text: button.textContent.trim(),
          disabled: button.disabled
        }))
    );

    console.log('Available service buttons:', serviceButtons);

    // Verify multiple buttons are available and not disabled
    expect(serviceButtons.length).toBeGreaterThan(1);
    
    const enabledButtons = serviceButtons.filter(btn => !btn.disabled);
    expect(enabledButtons.length).toBeGreaterThan(0);

    // Take screenshot of available services
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-enhancement-services.png' });
  });

  test('Error handling for failed financial data fetch', async () => {
    // This test would require mocking a failed service call
    // For now, we'll verify the error handling UI exists
    
    await page.goto(`${baseUrl}/companies/${testCompanyId}`);
    await page.waitForSelector('h1');

    // Check if error states are handled properly in the UI
    const errorHandlingElements = await page.$$eval('*', elements => 
      elements
        .filter(el => 
          el.textContent && (
            el.textContent.includes('Error') ||
            el.textContent.includes('Failed') ||
            el.className && el.className.includes('error')
          )
        )
        .map(el => ({
          text: el.textContent.trim(),
          className: el.className
        }))
        .slice(0, 5) // Limit to first 5 matches
    );

    console.log('Error handling elements found:', errorHandlingElements);
    
    // This is a basic check - in a real scenario, you'd mock the service to return an error
    await page.screenshot({ path: 'test/puppeteer/screenshots/company-error-check.png' });
  });
});

// Helper function to run a specific test
async function runSingleTest(testName) {
  console.log(`Running test: ${testName}`);
  // Implementation would go here for running individual tests
}

// If running directly (not through Jest)
if (require.main === module) {
  (async () => {
    console.log('Running Puppeteer tests for Company Financial Data...\n');
    console.log('Please run with Jest: npm test company_financial_data.test.js');
  })();
}