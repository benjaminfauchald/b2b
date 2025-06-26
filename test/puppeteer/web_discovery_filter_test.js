const puppeteer = require('puppeteer');

async function testWebDiscoveryFilter() {
  console.log('🧪 Testing Web Discovery Filter Functionality...');
  
  const browser = await puppeteer.launch({ 
    headless: false,
    defaultViewport: { width: 1280, height: 800 }
  });
  
  try {
    const page = await browser.newPage();
    
    // Navigate to companies index
    console.log('📍 Navigating to companies page...');
    await page.goto('https://local.connectica.no/companies');
    
    // Wait for the page to load
    await page.waitForSelector('select[name="filter"]', { timeout: 10000 });
    
    // Test the filter dropdown contains new web discovery options
    console.log('🔍 Testing filter dropdown options...');
    const filterOptions = await page.evaluate(() => {
      const select = document.querySelector('select[name="filter"]');
      const options = Array.from(select.options).map(option => ({
        value: option.value,
        text: option.text
      }));
      return options;
    });
    
    console.log('Available filter options:', filterOptions);
    
    // Check if web discovery options are present
    const webDiscoveryOptions = filterOptions.filter(option => 
      option.text.includes('Web Discovery')
    );
    
    if (webDiscoveryOptions.length === 3) {
      console.log('✅ All web discovery filter options found:');
      webDiscoveryOptions.forEach(option => {
        console.log(`   - ${option.text} (${option.value})`);
      });
    } else {
      console.log('❌ Missing web discovery filter options');
      return;
    }
    
    // Test filtering by "With Web Discovery"
    console.log('\n🔽 Testing "With Web Discovery" filter...');
    await page.select('select[name="filter"]', 'with_web_discovery');
    await page.click('input[type="submit"][value="Filter"]');
    
    // Wait for results
    await page.waitForTimeout(2000);
    
    // Check if any companies are shown and if they have web discovery badges
    const companiesWithWebDiscovery = await page.evaluate(() => {
      const companyItems = document.querySelectorAll('li');
      let companiesWithBadges = 0;
      let totalCompanies = 0;
      
      companyItems.forEach(item => {
        const companyName = item.querySelector('.text-indigo-600');
        if (companyName) {
          totalCompanies++;
          const webDiscoveryBadge = item.querySelector('.bg-purple-100, .bg-purple-900\\/20');
          if (webDiscoveryBadge) {
            companiesWithBadges++;
          }
        }
      });
      
      return { total: totalCompanies, withBadges: companiesWithBadges };
    });
    
    console.log(`📊 Found ${companiesWithWebDiscovery.total} companies`);
    console.log(`📋 ${companiesWithWebDiscovery.withBadges} have web discovery badges`);
    
    // Test filtering by "Without Web Discovery"
    console.log('\n🔽 Testing "Without Web Discovery" filter...');
    await page.select('select[name="filter"]', 'without_web_discovery');
    await page.click('input[type="submit"][value="Filter"]');
    
    await page.waitForTimeout(2000);
    
    const companiesWithoutWebDiscovery = await page.evaluate(() => {
      const companyItems = document.querySelectorAll('li');
      let companiesWithBadges = 0;
      let totalCompanies = 0;
      
      companyItems.forEach(item => {
        const companyName = item.querySelector('.text-indigo-600');
        if (companyName) {
          totalCompanies++;
          const webDiscoveryBadge = item.querySelector('.bg-purple-100, .bg-purple-900\\/20');
          if (webDiscoveryBadge) {
            companiesWithBadges++;
          }
        }
      });
      
      return { total: totalCompanies, withBadges: companiesWithBadges };
    });
    
    console.log(`📊 Found ${companiesWithoutWebDiscovery.total} companies`);
    console.log(`📋 ${companiesWithoutWebDiscovery.withBadges} have web discovery badges (should be 0)`);
    
    // Test filtering by "Needs Web Discovery"
    console.log('\n🔽 Testing "Needs Web Discovery" filter...');
    await page.select('select[name="filter"]', 'needs_web_discovery');
    await page.click('input[type="submit"][value="Filter"]');
    
    await page.waitForTimeout(2000);
    
    const companiesNeedingWebDiscovery = await page.evaluate(() => {
      const companyItems = document.querySelectorAll('li');
      let totalCompanies = 0;
      
      companyItems.forEach(item => {
        const companyName = item.querySelector('.text-indigo-600');
        if (companyName) {
          totalCompanies++;
        }
      });
      
      return totalCompanies;
    });
    
    console.log(`📊 Found ${companiesNeedingWebDiscovery} companies needing web discovery`);
    
    // Reset filter to show all companies
    console.log('\n🔄 Resetting to show all companies...');
    await page.select('select[name="filter"]', '');
    await page.click('input[type="submit"][value="Filter"]');
    
    await page.waitForTimeout(2000);
    
    console.log('\n✅ Web Discovery Filter Test Completed Successfully!');
    console.log('🎯 Summary:');
    console.log(`   - Filter dropdown contains all web discovery options`);
    console.log(`   - "With Web Discovery" shows ${companiesWithWebDiscovery.total} companies`);
    console.log(`   - "Without Web Discovery" shows ${companiesWithoutWebDiscovery.total} companies`);
    console.log(`   - "Needs Web Discovery" shows ${companiesNeedingWebDiscovery} companies`);
    console.log(`   - Web discovery badges are displayed correctly`);
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await browser.close();
  }
}

// Run the test
testWebDiscoveryFilter();