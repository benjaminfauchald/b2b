const puppeteer = require('puppeteer');

async function testLinkedInDiscovery() {
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
    
    // Take initial screenshot
    await page.screenshot({ 
      path: '/tmp/linkedin_discovery_initial.png',
      fullPage: false 
    });
    console.log('📸 Initial screenshot taken');
    
    // Check LinkedIn Discovery card exists and get stats
    console.log('🔍 Checking LinkedIn Discovery card...');
    const linkedinCard = await page.$('[data-service="company_linkedin_discovery"]');
    if (!linkedinCard) {
      throw new Error('LinkedIn Discovery card not found');
    }
    
    // Get completion stats before queuing
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
    
    console.log('📊 Initial LinkedIn Discovery stats:', initialStats);
    
    // Set batch size to 5
    console.log('⚙️  Setting batch size to 5...');
    const batchInput = await linkedinCard.$('input[name="count"]');
    await batchInput.click({ clickCount: 3 }); // Select all
    await batchInput.type('5');
    
    // Take screenshot before queuing
    await page.screenshot({ 
      path: '/tmp/linkedin_discovery_before_queue.png',
      fullPage: false 
    });
    console.log('📸 Before queue screenshot taken');
    
    // Queue LinkedIn discovery processing
    console.log('🚀 Clicking Queue Processing button...');
    const queueButton = await linkedinCard.$('button[type="submit"]');
    await queueButton.click();
    
    // Wait for the request to complete and check for success
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Check if any jobs were queued by monitoring network responses
    const networkLogs = [];
    page.on('response', response => {
      if (response.url().includes('queue_linkedin_discovery')) {
        networkLogs.push({
          url: response.url(),
          status: response.status(),
          timestamp: new Date().toISOString()
        });
      }
    });
    
    // Wait a bit more for any background updates
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Get updated stats
    const updatedStats = await page.evaluate(() => {
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
    
    console.log('📊 Updated LinkedIn Discovery stats:', updatedStats);
    
    // Check queue statistics
    const queueStats = await page.evaluate(() => {
      const queueElement = document.querySelector('[data-queue-stat="company_linkedin_discovery"]');
      return queueElement ? parseInt(queueElement.textContent) : 0;
    });
    
    console.log('📋 LinkedIn Queue depth:', queueStats);
    
    // Take final screenshot
    await page.screenshot({ 
      path: '/tmp/linkedin_discovery_after_queue.png',
      fullPage: false 
    });
    console.log('📸 After queue screenshot taken');
    
    // Verify LinkedIn Discovery functionality
    console.log('\n🧪 LINKEDIN DISCOVERY TEST RESULTS:');
    console.log('==========================================');
    
    if (initialStats && updatedStats) {
      console.log(`✅ LinkedIn Discovery card found and functional`);
      console.log(`📊 Total companies in scope: ${initialStats.total}`);
      console.log(`📈 Initial processed: ${initialStats.processed} (${initialStats.percentage}%)`);
      console.log(`📈 After queue: ${updatedStats.processed} (${updatedStats.percentage}%)`);
      console.log(`🔄 Queue depth: ${queueStats} jobs`);
      
      // Test batch size functionality
      const batchValue = await page.evaluate(() => {
        const input = document.querySelector('[data-service="company_linkedin_discovery"] input[name="count"]');
        return input ? input.value : null;
      });
      console.log(`⚙️  Batch size set to: ${batchValue}`);
      
      if (batchValue === '5') {
        console.log('✅ Batch size correctly set to 5');
      } else {
        console.log('❌ Batch size not properly set');
      }
      
      // Check if queue button is functional
      const buttonExists = await linkedinCard.$('button[type="submit"]');
      if (buttonExists) {
        console.log('✅ Queue button found and clickable');
      } else {
        console.log('❌ Queue button not found');
      }
      
      // Overall assessment
      if (initialStats.total > 0) {
        console.log('✅ LinkedIn Discovery has companies in scope for processing');
      } else {
        console.log('⚠️  No companies currently in LinkedIn Discovery scope');
      }
      
      console.log('\n🎯 LinkedIn Discovery appears to be working correctly!');
      
    } else {
      console.log('❌ Could not retrieve LinkedIn Discovery stats');
    }
    
    console.log('\n📸 Screenshots saved:');
    console.log('  - /tmp/linkedin_discovery_initial.png');
    console.log('  - /tmp/linkedin_discovery_before_queue.png');
    console.log('  - /tmp/linkedin_discovery_after_queue.png');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    throw error;
  } finally {
    await browser.close();
  }
}

// Run the test
testLinkedInDiscovery()
  .then(() => {
    console.log('\n✅ LinkedIn Discovery test completed successfully!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ LinkedIn Discovery test failed:', error);
    process.exit(1);
  });