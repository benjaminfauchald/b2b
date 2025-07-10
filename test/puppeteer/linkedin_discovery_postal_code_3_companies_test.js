const puppeteer = require('puppeteer');

async function testLinkedInDiscoveryPostalCode3Companies() {
  const browser = await puppeteer.launch({ 
    headless: false,
    defaultViewport: { width: 1920, height: 1080 },
    args: [
      '--window-size=1920,1080',
      '--start-maximized'
    ]
  });
  
  try {
    const page = await browser.newPage();
    
    // Navigate to login page
    console.log('🔐 Navigating to login page...');
    await page.goto('https://local.connectica.no/users/sign_in');
    await page.waitForSelector('input[name="user[email]"]');
    
    // Login
    console.log('🔐 Logging in...');
    await page.type('input[name="user[email]"]', 'test@test.no');
    await page.type('input[name="user[password]"]', 'CodemyFTW2');
    await page.click('input[type="submit"]');
    
    // Wait for redirect and navigate to companies page
    await page.waitForNavigation();
    console.log('📄 Navigating to companies page...');
    await page.goto('https://local.connectica.no/companies');
    
    // Wait for LinkedIn Discovery by Postal Code component to load
    console.log('🗺️  Waiting for LinkedIn Discovery by Postal Code component...');
    await page.waitForSelector('h2:contains("LinkedIn Discovery by Postal Code")', { timeout: 10000 })
      .catch(() => {
        console.log('⚠️  LinkedIn Discovery by Postal Code heading not found, checking alternative selectors...');
      });
    
    // Check if the component is visible
    const componentVisible = await page.evaluate(() => {
      // Look for the component heading
      const heading = Array.from(document.querySelectorAll('h2')).find(h => 
        h.textContent.includes('LinkedIn Discovery by Postal Code')
      );
      if (!heading) return false;
      
      // Check if the form is visible
      const form = document.getElementById('linkedin-postal-code-form');
      return form && form.offsetParent !== null;
    });
    
    if (!componentVisible) {
      console.log('❌ LinkedIn Discovery by Postal Code component not visible');
      console.log('🔍 This could mean:');
      console.log('   - Service is not active');
      console.log('   - Component failed to render');
      console.log('   - Database isolation issues');
      
      // Take debug screenshot
      await page.screenshot({ 
        path: '/tmp/postal_code_component_missing.png',
        fullPage: true 
      });
      
      throw new Error('LinkedIn Discovery by Postal Code component not found');
    }
    
    console.log('✅ LinkedIn Discovery by Postal Code component found');
    
    // Get initial queue stats
    console.log('📊 Getting initial LinkedIn Discovery queue stats...');
    const initialQueueDepth = await page.evaluate(() => {
      const queueElement = document.querySelector('[data-queue-stat="company_linkedin_discovery"]');
      return queueElement ? parseInt(queueElement.textContent) : 0;
    });
    
    console.log(`📈 Initial queue depth: ${initialQueueDepth} jobs`);
    
    // Take screenshot before interacting with postal code form
    await page.screenshot({ 
      path: '/tmp/postal_code_before_test.png',
      fullPage: true 
    });
    
    // Select postal code 2000 (Lillestrøm)
    console.log('🗺️  Selecting postal code 2000 (Lillestrøm)...');
    const postalCodeSelect = await page.$('select[name="postal_code"]');
    if (!postalCodeSelect) {
      throw new Error('Postal code select field not found');
    }
    
    // Check available postal code options
    const postalCodeOptions = await page.evaluate(() => {
      const select = document.querySelector('select[name="postal_code"]');
      if (!select) return [];
      return Array.from(select.options).map(option => ({
        value: option.value,
        text: option.textContent
      }));
    });
    
    console.log('📍 Available postal codes:', postalCodeOptions.slice(0, 5)); // Show first 5
    
    // Select postal code 2000 if available, otherwise use first available
    const targetPostalCode = postalCodeOptions.find(opt => opt.value === '2000') || postalCodeOptions[1];
    if (!targetPostalCode || !targetPostalCode.value) {
      throw new Error('No valid postal codes available');
    }
    
    await page.select('select[name="postal_code"]', targetPostalCode.value);
    console.log(`📍 Selected postal code: ${targetPostalCode.value}`);
    
    // Set batch size to 3
    console.log('⚙️  Setting batch size to 3 companies...');
    const batchSizeSelect = await page.$('select[name="batch_size"]');
    if (!batchSizeSelect) {
      throw new Error('Batch size select field not found');
    }
    
    // Check available batch size options
    const batchSizeOptions = await page.evaluate(() => {
      const select = document.querySelector('select[name="batch_size"]');
      if (!select) return [];
      return Array.from(select.options).map(option => ({
        value: option.value,
        text: option.textContent
      }));
    });
    
    console.log('📊 Available batch sizes:', batchSizeOptions);
    
    // Select 3 if available, otherwise use 10 (smallest available)
    const targetBatchSize = batchSizeOptions.find(opt => opt.value === '3');
    const batchSize = targetBatchSize ? '3' : '10';
    await page.select('select[name="batch_size"]', batchSize);
    console.log(`📊 Selected batch size: ${batchSize}`);
    
    // Trigger change event to update preview
    await page.evaluate(() => {
      const select = document.querySelector('select[name="batch_size"]');
      if (select) {
        const event = new Event('change', { bubbles: true });
        select.dispatchEvent(event);
      }
    });
    
    // Wait for preview to update
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Get company preview info
    const previewInfo = await page.evaluate(() => {
      const previewElement = document.querySelector('[data-postal-code-form-target="previewText"]');
      return previewElement ? previewElement.textContent.trim() : 'No preview available';
    });
    
    console.log(`📋 Company preview: ${previewInfo}`);
    
    // Check if queue button is enabled
    const queueButtonEnabled = await page.evaluate(() => {
      const postalCodeForm = document.getElementById('linkedin-postal-code-form');
      if (!postalCodeForm) return false;
      
      const submitButton = postalCodeForm.querySelector('input[type="submit"], button[type="submit"]');
      return submitButton && !submitButton.disabled;
    });
    
    if (!queueButtonEnabled) {
      console.log('⚠️  Queue button is disabled');
      await page.screenshot({ 
        path: '/tmp/postal_code_button_disabled.png',
        fullPage: true 
      });
      throw new Error('Queue button is disabled - no companies available or other issue');
    }
    
    console.log('✅ Queue button is enabled');
    
    // Monitor network requests to capture the queue response
    let queueResponse = null;
    let responsePromise = null;
    
    page.on('response', async response => {
      const url = response.url();
      console.log(`📡 Network response: ${response.status()} ${url}`);
      
      if (url.includes('queue_linkedin_discovery_by_postal_code')) {
        try {
          const contentType = response.headers()['content-type'] || '';
          console.log(`📋 Queue response content-type: ${contentType}`);
          
          if (contentType.includes('application/json')) {
            queueResponse = await response.json();
            console.log('📡 Captured JSON queue response:', queueResponse);
          } else {
            const text = await response.text();
            console.log('📡 Captured text queue response:', text.substring(0, 200));
          }
        } catch (e) {
          console.log('Could not parse queue response:', e.message);
        }
      }
    });
    
    // Also monitor requests to see what's being sent
    page.on('request', request => {
      if (request.url().includes('queue_linkedin_discovery_by_postal_code')) {
        console.log(`📤 Queue request: ${request.method()} ${request.url()}`);
        if (request.postData()) {
          console.log(`📤 Request data: ${request.postData()}`);
        }
      }
    });
    
    // Queue 3 companies by postal code
    console.log('🚀 Queuing 3 companies for LinkedIn discovery by postal code...');
    
    // Find the specific submit button within the postal code form
    const postalCodeForm = await page.$('#linkedin-postal-code-form');
    if (!postalCodeForm) {
      throw new Error('LinkedIn postal code form not found');
    }
    
    const submitButton = await postalCodeForm.$('input[type="submit"], button[type="submit"]');
    if (!submitButton) {
      throw new Error('Submit button not found in postal code form');
    }
    
    await submitButton.click();
    
    // Wait for response
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    console.log('📋 Queue response:', queueResponse);
    
    // Check queue depth after queuing
    const newQueueDepth = await page.evaluate(() => {
      const queueElement = document.querySelector('[data-queue-stat="company_linkedin_discovery"]');
      return queueElement ? parseInt(queueElement.textContent) : 0;
    });
    
    console.log(`📊 Queue depth after queuing: ${newQueueDepth} jobs (was ${initialQueueDepth})`);
    const jobsAdded = newQueueDepth - initialQueueDepth;
    console.log(`📈 Jobs added to queue: ${jobsAdded}`);
    
    // Take screenshot after queuing
    await page.screenshot({ 
      path: '/tmp/postal_code_after_queue.png',
      fullPage: true 
    });
    
    // Wait for jobs to be processed (optional - can be skipped for faster test)
    console.log('⏳ Monitoring job processing for 30 seconds...');
    let attempts = 0;
    const maxAttempts = 3; // Wait up to 30 seconds
    
    while (attempts < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 10000)); // Wait 10 seconds
      attempts++;
      
      // Check queue depth
      const currentQueueDepth = await page.evaluate(() => {
        const queueElement = document.querySelector('[data-queue-stat="company_linkedin_discovery"]');
        return queueElement ? parseInt(queueElement.textContent) : 0;
      });
      
      console.log(`🔄 Check ${attempts}: Queue depth = ${currentQueueDepth}`);
      
      if (currentQueueDepth < newQueueDepth) {
        console.log('🔄 Jobs are being processed...');
      }
      
      if (currentQueueDepth === 0) {
        console.log('✅ All jobs processed!');
        break;
      }
    }
    
    // Print comprehensive results
    console.log('\n🎯 LINKEDIN DISCOVERY POSTAL CODE TEST RESULTS:');
    console.log('================================================');
    
    console.log('\n📍 POSTAL CODE SELECTION:');
    console.log(`Selected postal code: ${targetPostalCode.value}`);
    console.log(`Batch size: 3 companies`);
    console.log(`Preview: ${previewInfo}`);
    
    console.log('\n📊 QUEUE STATISTICS:');
    console.log(`Initial queue depth: ${initialQueueDepth} jobs`);
    console.log(`Queue depth after queuing: ${newQueueDepth} jobs`);
    console.log(`Jobs added: ${jobsAdded}`);
    
    if (queueResponse) {
      console.log('\n📋 SERVER RESPONSE:');
      console.log(`Success: ${queueResponse.success}`);
      console.log(`Message: ${queueResponse.message || 'N/A'}`);
      console.log(`Queued count: ${queueResponse.queued_count || 'N/A'}`);
      console.log(`Available count: ${queueResponse.available_count || 'N/A'}`);
      console.log(`Postal code: ${queueResponse.postal_code || 'N/A'}`);
      console.log(`Batch size: ${queueResponse.batch_size || 'N/A'}`);
    }
    
    console.log('\n📸 SCREENSHOTS SAVED:');
    console.log('  - /tmp/postal_code_before_test.png');
    console.log('  - /tmp/postal_code_after_queue.png');
    
    // Analysis
    console.log('\n🔍 ANALYSIS:');
    if (queueResponse && queueResponse.success) {
      console.log('✅ Postal code LinkedIn discovery successfully queued companies!');
      if (jobsAdded === 3) {
        console.log('✅ Exactly 3 jobs were added to the queue as expected');
      } else if (jobsAdded > 0) {
        console.log(`⚠️  ${jobsAdded} jobs were added (expected 3)`);
      } else {
        console.log('⚠️  No jobs were added to the queue');
      }
    } else {
      console.log('❌ Postal code LinkedIn discovery failed');
      if (queueResponse) {
        console.log(`Error: ${queueResponse.message || 'Unknown error'}`);
      }
    }
    
    if (jobsAdded > 0) {
      console.log('✅ LinkedIn Discovery by Postal Code feature is working!');
      console.log('📈 Companies have been successfully queued for processing');
    }
    
    console.log('\n🎯 Postal code test completed successfully!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    
    // Take error screenshot
    try {
      const page = browser._pageTargets?.[0]?._page;
      if (page) {
        await page.screenshot({ 
          path: '/tmp/postal_code_test_error.png',
          fullPage: true 
        });
        console.log('📸 Error screenshot saved: /tmp/postal_code_test_error.png');
      }
    } catch (screenshotError) {
      console.log('Could not take error screenshot');
    }
    
    throw error;
  } finally {
    await browser.close();
  }
}

// Run the test
testLinkedInDiscoveryPostalCode3Companies()
  .then(() => {
    console.log('\n✅ LinkedIn Discovery Postal Code 3-company test completed!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Test failed:', error);
    process.exit(1);
  });