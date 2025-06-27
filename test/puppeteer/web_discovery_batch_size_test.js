const puppeteer = require('puppeteer');

async function testWebDiscoveryBatchSize() {
  const browser = await puppeteer.launch({ 
    headless: false,
    devtools: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  try {
    const page = await browser.newPage();
    
    // Enable console logging from the page
    page.on('console', msg => {
      console.log('PAGE LOG:', msg.text());
    });
    
    // Navigate to the companies page
    console.log('🌐 Navigating to companies page...');
    await page.goto('https://local.connectica.no/companies', { 
      waitUntil: 'networkidle0',
      timeout: 30000 
    });
    
    // Wait for the page to load completely
    await page.waitForTimeout(2000);
    
    // Find the Web Discovery form
    console.log('🔍 Looking for Web Discovery form...');
    const webDiscoveryForm = await page.$('[data-service="company_web_discovery"] form');
    
    if (!webDiscoveryForm) {
      throw new Error('Web Discovery form not found');
    }
    
    // Find the count input field
    const countInput = await page.$('[data-service="company_web_discovery"] input[name="count"]');
    if (!countInput) {
      throw new Error('Count input field not found');
    }
    
    // Get the current value and clear it
    const currentValue = await page.evaluate(input => input.value, countInput);
    console.log('📊 Current batch size value:', currentValue);
    
    // Clear the input and set it to 5
    console.log('✏️ Setting batch size to 5...');
    await page.evaluate(input => {
      input.focus();
      input.select();
      input.value = '5';
    }, countInput);
    
    // Verify the value was set
    const newValue = await page.evaluate(input => input.value, countInput);
    console.log('✅ New batch size value:', newValue);
    
    // Find the submit button
    const submitButton = await page.$('[data-service="company_web_discovery"] button[type="submit"]');
    if (!submitButton) {
      throw new Error('Submit button not found');
    }
    
    // Listen for network requests to capture the form submission
    const formSubmissionPromise = new Promise((resolve) => {
      page.on('response', async (response) => {
        if (response.url().includes('/companies/queue_web_discovery') && response.request().method() === 'POST') {
          const responseText = await response.text();
          console.log('📤 Form submission response:', responseText);
          resolve(response);
        }
      });
    });
    
    // Capture form data being sent
    page.on('request', request => {
      if (request.url().includes('/companies/queue_web_discovery') && request.method() === 'POST') {
        const postData = request.postData();
        console.log('📋 Form data being sent:', postData);
      }
    });
    
    // Click the submit button
    console.log('🚀 Submitting form...');
    await submitButton.click();
    
    // Wait for the form submission to complete
    await formSubmissionPromise;
    
    // Wait a bit to see the result
    await page.waitForTimeout(3000);
    
    console.log('✅ Test completed successfully');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    throw error;
  } finally {
    await browser.close();
  }
}

// Run the test
testWebDiscoveryBatchSize().catch(console.error);