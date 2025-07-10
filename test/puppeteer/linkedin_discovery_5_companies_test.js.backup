const puppeteer = require('puppeteer');

async function testLinkedInDiscovery5Companies() {
  const browser = await puppeteer.launch({ 
    headless: false,
    defaultViewport: { width: 1400, height: 900 }
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
    await page.waitForSelector('[data-service="company_linkedin_discovery"]');
    
    // Get initial stats
    console.log('📊 Getting initial LinkedIn Discovery stats...');
    const initialStats = await page.evaluate(() => {
      const frame = document.querySelector('#company_linkedin_discovery_stats');
      if (!frame) return null;
      
      const completionText = frame.textContent || '';
      const percentageMatch = completionText.match(/(\d+\.?\d*)%/);
      const processedMatch = completionText.match(/(\d+) of (\d+) companies processed/);
      
      return {
        percentage: percentageMatch ? parseFloat(percentageMatch[1]) : 0,
        processed: processedMatch ? parseInt(processedMatch[1]) : 0,
        total: processedMatch ? parseInt(processedMatch[2]) : 0,
        fullText: completionText
      };
    });
    
    console.log('📈 Initial stats:', initialStats);
    
    // Set batch size to 5 and queue processing
    console.log('⚙️  Setting batch size to 5 companies...');
    const linkedinCard = await page.$('[data-service="company_linkedin_discovery"]');
    const batchInput = await linkedinCard.$('input[name="count"]');
    await batchInput.click({ clickCount: 3 }); // Select all
    await batchInput.type('5');
    
    // Take screenshot before queuing
    await page.screenshot({ 
      path: '/tmp/linkedin_before_5_companies.png',
      fullPage: false 
    });
    
    // Monitor network requests to capture the queue response
    let queueResponse = null;
    page.on('response', async response => {
      if (response.url().includes('queue_linkedin_discovery')) {
        try {
          queueResponse = await response.json();
        } catch (e) {
          console.log('Could not parse queue response as JSON');
        }
      }
    });
    
    // Queue processing
    console.log('🚀 Queuing 5 companies for LinkedIn discovery...');
    const queueButton = await linkedinCard.$('button[type="submit"]');
    await queueButton.click();
    
    // Wait for response
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    console.log('📋 Queue response:', queueResponse);
    
    // Check queue depth after queuing
    const queueDepth = await page.evaluate(() => {
      const queueElement = document.querySelector('[data-queue-stat="company_linkedin_discovery"]');
      return queueElement ? parseInt(queueElement.textContent) : 0;
    });
    
    console.log('📊 Queue depth after queuing:', queueDepth, 'jobs');
    
    // Wait for jobs to be processed (Sidekiq processing)
    console.log('⏳ Waiting for LinkedIn discovery jobs to process...');
    let processingComplete = false;
    let attempts = 0;
    const maxAttempts = 30; // Wait up to 5 minutes
    
    while (!processingComplete && attempts < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 10000)); // Wait 10 seconds
      attempts++;
      
      // Check queue depth
      const currentQueueDepth = await page.evaluate(() => {
        const queueElement = document.querySelector('[data-queue-stat="company_linkedin_discovery"]');
        return queueElement ? parseInt(queueElement.textContent) : 0;
      });
      
      console.log(`🔄 Attempt ${attempts}: Queue depth = ${currentQueueDepth}`);
      
      if (currentQueueDepth === 0) {
        processingComplete = true;
        console.log('✅ All jobs processed!');
      }
    }
    
    if (!processingComplete) {
      console.log('⚠️  Jobs still processing after maximum wait time');
    }
    
    // Get final stats
    console.log('📊 Getting final LinkedIn Discovery stats...');
    await page.reload(); // Refresh to get latest stats
    await page.waitForSelector('[data-service="company_linkedin_discovery"]');
    
    const finalStats = await page.evaluate(() => {
      const frame = document.querySelector('#company_linkedin_discovery_stats');
      if (!frame) return null;
      
      const completionText = frame.textContent || '';
      const percentageMatch = completionText.match(/(\d+\.?\d*)%/);
      const processedMatch = completionText.match(/(\d+) of (\d+) companies processed/);
      
      return {
        percentage: percentageMatch ? parseFloat(percentageMatch[1]) : 0,
        processed: processedMatch ? parseInt(processedMatch[1]) : 0,
        total: processedMatch ? parseInt(processedMatch[2]) : 0,
        fullText: completionText
      };
    });
    
    console.log('📈 Final stats:', finalStats);
    
    // Take final screenshot
    await page.screenshot({ 
      path: '/tmp/linkedin_after_5_companies.png',
      fullPage: false 
    });
    
    // Navigate to check individual company results
    console.log('🔍 Checking companies with LinkedIn data...');
    
    // Filter for companies with LinkedIn
    await page.select('select[name="filter"]', 'with_linkedin');
    await page.click('input[type="submit"][value="Filter"]');
    await page.waitForSelector('.divide-y');
    
    // Get companies with LinkedIn data
    const companiesWithLinkedIn = await page.evaluate(() => {
      const rows = document.querySelectorAll('li');
      const companies = [];
      
      rows.forEach(row => {
        const nameElement = row.querySelector('[class*="text-indigo-600"]:not(a)');
        const linkedinElement = row.querySelector('[class*="LinkedIn"]');
        const regElement = row.querySelector('span');
        
        if (nameElement && linkedinElement) {
          companies.push({
            name: nameElement.textContent.trim(),
            registration: regElement ? regElement.textContent.trim() : 'N/A',
            hasLinkedIn: true
          });
        }
      });
      
      return companies.slice(0, 10); // Get first 10 matches
    });
    
    // Take screenshot of companies with LinkedIn
    await page.screenshot({ 
      path: '/tmp/companies_with_linkedin.png',
      fullPage: true 
    });
    
    // Print comprehensive results
    console.log('\n🎯 LINKEDIN DISCOVERY 5-COMPANY TEST RESULTS:');
    console.log('================================================');
    
    console.log('\n📊 STATISTICS COMPARISON:');
    console.log(`Initial processed: ${initialStats.processed} companies (${initialStats.percentage}%)`);
    console.log(`Final processed: ${finalStats.processed} companies (${finalStats.percentage}%)`);
    console.log(`Companies added: ${finalStats.processed - initialStats.processed}`);
    console.log(`Total scope: ${finalStats.total} companies`);
    
    if (queueResponse) {
      console.log('\n📋 QUEUE RESPONSE:');
      console.log(`Success: ${queueResponse.success}`);
      console.log(`Message: ${queueResponse.message}`);
      console.log(`Queued count: ${queueResponse.queued_count || 'N/A'}`);
      console.log(`Available count: ${queueResponse.available_count || 'N/A'}`);
    }
    
    console.log('\n🏢 COMPANIES WITH LINKEDIN DATA:');
    if (companiesWithLinkedIn.length > 0) {
      companiesWithLinkedIn.forEach((company, index) => {
        console.log(`${index + 1}. ${company.name} (${company.registration})`);
      });
      console.log(`\nTotal companies with LinkedIn: ${companiesWithLinkedIn.length} found`);
    } else {
      console.log('No companies with LinkedIn data found in current page');
    }
    
    console.log('\n📸 SCREENSHOTS SAVED:');
    console.log('  - /tmp/linkedin_before_5_companies.png');
    console.log('  - /tmp/linkedin_after_5_companies.png'); 
    console.log('  - /tmp/companies_with_linkedin.png');
    
    // Analysis
    console.log('\n🔍 ANALYSIS:');
    if (finalStats.processed > initialStats.processed) {
      console.log('✅ LinkedIn discovery successfully processed companies!');
      console.log(`📈 Processed ${finalStats.processed - initialStats.processed} additional companies`);
    } else {
      console.log('⚠️  No increase in processed companies detected');
      console.log('🔍 This could mean:');
      console.log('   - Jobs are still processing');
      console.log('   - No suitable companies were found');
      console.log('   - Service configuration issues');
    }
    
    if (companiesWithLinkedIn.length > 0) {
      console.log('✅ Found companies with LinkedIn data in the system');
    }
    
    console.log('\n🎯 Test completed successfully!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    throw error;
  } finally {
    await browser.close();
  }
}

// Run the test
testLinkedInDiscovery5Companies()
  .then(() => {
    console.log('\n✅ LinkedIn Discovery 5-company test completed!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Test failed:', error);
    process.exit(1);
  });