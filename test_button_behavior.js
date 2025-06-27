// Test script to debug the queue testing button behavior
const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch({ 
    headless: false, // Show browser so we can see what happens
    devtools: true   // Open dev tools to see console logs
  });
  
  const page = await browser.newPage();
  
  // Listen for console logs from the page
  page.on('console', msg => {
    console.log('PAGE LOG:', msg.text());
  });
  
  // Listen for JavaScript errors
  page.on('pageerror', error => {
    console.log('PAGE ERROR:', error.message);
  });
  
  try {
    console.log('Navigating to domains page...');
    await page.goto('http://127.0.0.1:3000/domains', { 
      waitUntil: 'networkidle2' 
    });
    
    console.log('Waiting for page to load...');
    await page.waitForTimeout(2000);
    
    // Check if the service queue controller is loaded
    console.log('Checking if Stimulus controllers are loaded...');
    const stimulusLoaded = await page.evaluate(() => {
      return window.Stimulus !== undefined;
    });
    console.log('Stimulus loaded:', stimulusLoaded);
    
    // Look for the DNS testing form
    console.log('Looking for DNS testing form...');
    const dnsForm = await page.$('[data-controller="service-queue"]');
    if (!dnsForm) {
      console.log('ERROR: DNS testing form with service-queue controller not found!');
      await browser.close();
      return;
    }
    console.log('Found DNS testing form with service-queue controller');
    
    // Check if the submit button exists
    const submitButton = await page.$('[data-service-queue-target="submitButton"]');
    if (!submitButton) {
      console.log('ERROR: Submit button not found!');
      await browser.close();
      return;
    }
    console.log('Found submit button');
    
    // Get initial button state
    const initialButtonState = await page.evaluate((btn) => {
      return {
        disabled: btn.disabled,
        innerHTML: btn.innerHTML,
        opacity: btn.style.opacity
      };
    }, submitButton);
    console.log('Initial button state:', initialButtonState);
    
    // Click the button and immediately check state
    console.log('Clicking the Queue Testing button...');
    await submitButton.click();
    
    // Check button state immediately after click
    await page.waitForTimeout(100); // Small delay
    const afterClickState = await page.evaluate((btn) => {
      return {
        disabled: btn.disabled,
        innerHTML: btn.innerHTML,
        opacity: btn.style.opacity
      };
    }, submitButton);
    console.log('Button state after click:', afterClickState);
    
    // Wait a bit more and check again
    await page.waitForTimeout(1000);
    const laterState = await page.evaluate((btn) => {
      return {
        disabled: btn.disabled,
        innerHTML: btn.innerHTML,
        opacity: btn.style.opacity
      };
    }, submitButton);
    console.log('Button state after 1 second:', laterState);
    
    // Check for any network requests
    console.log('Checking current URL...');
    const currentUrl = page.url();
    console.log('Current URL:', currentUrl);
    
    if (currentUrl.includes('queue_dns_testing')) {
      console.log('ERROR: Page navigated instead of using AJAX!');
    } else {
      console.log('SUCCESS: Page did not navigate - AJAX likely working');
    }
    
    // Wait a bit longer to see final state
    await page.waitForTimeout(3000);
    const finalState = await page.evaluate((btn) => {
      return {
        disabled: btn.disabled,
        innerHTML: btn.innerHTML,
        opacity: btn.style.opacity
      };
    }, submitButton);
    console.log('Final button state:', finalState);
    
  } catch (error) {
    console.error('Test error:', error);
  }
  
  console.log('Test completed. Press any key to close browser...');
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.on('data', () => {
    browser.close();
    process.exit();
  });
})();