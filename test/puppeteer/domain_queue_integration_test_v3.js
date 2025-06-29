const puppeteer = require('puppeteer');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Rails helper functions
function runRailsHelper(command, args = '') {
  try {
    const output = execSync(
      `bundle exec rails runner test/puppeteer/rails_helpers.rb ${command} ${args}`,
      {
        encoding: 'utf8',
        cwd: '/Users/benjamin/Documents/Projects/b2b',
        stdio: ['pipe', 'pipe', 'ignore'] // Ignore stderr
      }
    );
    // The output should be a file path
    const outputFile = output.trim();
    if (fs.existsSync(outputFile)) {
      const result = JSON.parse(fs.readFileSync(outputFile, 'utf8'));
      fs.unlinkSync(outputFile); // Clean up
      return result;
    }
    return null;
  } catch (error) {
    console.error(`Rails helper failed for command: ${command}`, error.message);
    return null;
  }
}

// Get Sidekiq stats using dedicated script
function getSidekiqStats() {
  try {
    const output = execSync(
      'ruby tmp/get_sidekiq_stats.rb 2>/dev/null',
      {
        encoding: 'utf8',
        cwd: '/Users/benjamin/Documents/Projects/b2b'
      }
    );
    // Extract JSON from output (may have logging before it)
    const lines = output.trim().split('\n');
    const jsonLine = lines[lines.length - 1]; // Last line should be JSON
    return JSON.parse(jsonLine);
  } catch (error) {
    console.error('Failed to get Sidekiq stats:', error.message);
    return null;
  }
}

async function runTest() {
  console.log('🚀 Starting Domain Queue Integration Test\n');
  
  // Create test results directory in tmp
  const testResultsDir = path.join('/Users/benjamin/Documents/Projects/b2b/tmp/test_results');
  fs.mkdirSync(testResultsDir, { recursive: true });
  
  // Clean up any existing test domains first
  console.log('🧹 Cleaning up any existing test domains...');
  const cleanup = runRailsHelper('cleanup');
  if (cleanup) {
    console.log(`Deleted ${cleanup.deleted_count} existing test domains`);
  }
  
  // Create test domains
  console.log('\n📝 Creating 50 test domains...');
  const domainIds = runRailsHelper('create_domains', '50');
  if (!domainIds) {
    console.error('Failed to create test domains');
    return;
  }
  console.log(`✅ Created ${domainIds.length} test domains\n`);
  
  // Check initial stats
  console.log('📊 Initial Statistics:');
  const initialSidekiq = getSidekiqStats();
  const initialDomainsNeeding = runRailsHelper('domains_needing');
  console.log('Sidekiq:', initialSidekiq);
  console.log('Domains needing service:', initialDomainsNeeding);
  console.log('');
  
  // Launch browser
  const browser = await puppeteer.launch({
    headless: false,
    defaultViewport: { width: 1400, height: 900 }
  });
  
  const page = await browser.newPage();
  
  try {
    // Login
    console.log('🔐 Logging in as admin...');
    await page.goto('https://local.connectica.no/users/sign_in');
    await page.waitForSelector('#user_email');
    await page.type('#user_email', 'admin@example.com');
    await page.type('#user_password', 'Charcoal2020!');
    await page.click('button[type="submit"]');
    await page.waitForNavigation();
    console.log('✅ Logged in successfully\n');
    
    // Navigate to domains page
    console.log('📍 Navigating to domains page...');
    await page.goto('https://local.connectica.no/domains');
    await page.waitForSelector('[data-stat="domain_dns_testing"]', { timeout: 10000 });
    
    // Wait for stats to load
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Take initial screenshot
    await page.screenshot({ 
      path: path.join(testResultsDir, 'domain_queue_initial.png'),
      fullPage: true 
    });
    console.log('📸 Initial screenshot saved\n');
    
    // Get initial UI stats
    console.log('📊 Reading initial UI statistics...');
    const initialUIStats = await page.evaluate(() => {
      return {
        dns_queue: document.querySelector('[data-stat="domain_dns_testing"]')?.textContent || '0',
        mx_queue: document.querySelector('[data-stat="domain_mx_testing"]')?.textContent || '0',
        a_record_queue: document.querySelector('[data-stat="DomainARecordTestingService"]')?.textContent || '0',
        web_content_queue: document.querySelector('[data-stat="DomainWebContentExtractionWorker"]')?.textContent || '0',
        total_processed: document.querySelector('[data-stat="processed"]')?.textContent || '0',
        dns_not_tested: document.querySelector('[data-available-count="domain_testing"]')?.textContent || '0'
      };
    });
    console.log('Initial UI Stats:', initialUIStats);
    console.log('');
    
    // Queue 50 DNS tests
    console.log('🚀 Queueing 50 domains for DNS testing...');
    
    // Find the DNS testing input and button
    await page.waitForSelector('[data-service="domain_testing"]');
    
    // Clear and type the count
    const inputSelector = '[data-service="domain_testing"] input[type="number"]';
    await page.waitForSelector(inputSelector);
    await page.click(inputSelector, { clickCount: 3 });
    await page.type(inputSelector, '50');
    
    // Click the submit button
    const buttonSelector = '[data-service="domain_testing"] button[type="submit"]';
    await page.click(buttonSelector);
    
    // Wait for success toast or error
    try {
      await page.waitForSelector('.bg-green-500, .bg-red-500', { timeout: 10000 });
      
      // Check if we got success or error
      const toastInfo = await page.evaluate(() => {
        const successToast = document.querySelector('.bg-green-500');
        const errorToast = document.querySelector('.bg-red-500');
        if (successToast) {
          return { type: 'success', message: successToast.textContent.trim() };
        }
        if (errorToast) {
          return { type: 'error', message: errorToast.textContent.trim() };
        }
        return null;
      });
      
      if (toastInfo?.type === 'success') {
        console.log(`✅ Successfully queued domains: ${toastInfo.message}\n`);
      } else if (toastInfo?.type === 'error') {
        console.log(`❌ Failed to queue domains: ${toastInfo.message}\n`);
      }
      
      // Wait a bit for stats to update
      await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (error) {
      console.log('⚠️  No toast message appeared, continuing anyway\n');
    }
    
    // Take screenshot after queueing
    await page.screenshot({ 
      path: path.join(testResultsDir, 'domain_queue_after_queue.png'),
      fullPage: true 
    });
    
    // Monitor stats for 30 seconds
    console.log('📊 Monitoring statistics for 30 seconds...\n');
    const statSnapshots = [];
    const auditLogSnapshots = [];
    
    for (let i = 0; i < 6; i++) {
      await new Promise(resolve => setTimeout(resolve, 5000)); // Wait 5 seconds
      
      // Get UI stats
      const uiStats = await page.evaluate(() => {
        return {
          dns_queue: document.querySelector('[data-stat="domain_dns_testing"]')?.textContent || '0',
          mx_queue: document.querySelector('[data-stat="domain_mx_testing"]')?.textContent || '0',
          a_record_queue: document.querySelector('[data-stat="DomainARecordTestingService"]')?.textContent || '0',
          web_content_queue: document.querySelector('[data-stat="DomainWebContentExtractionWorker"]')?.textContent || '0',
          total_processed: document.querySelector('[data-stat="processed"]')?.textContent || '0',
          dns_not_tested: document.querySelector('[data-available-count="domain_testing"]')?.textContent || '0',
          dns_queue_in_button: document.querySelector('[data-queue-stat="domain_dns_testing"]')?.textContent || '0'
        };
      });
      
      // Get backend stats
      const sidekiqStats = getSidekiqStats() || {};
      const domainsNeeding = runRailsHelper('domains_needing') || {};
      const processedStats = runRailsHelper('processed_stats') || {};
      const recentLogs = runRailsHelper('audit_logs', '10') || [];
      
      const snapshot = {
        time: new Date().toISOString(),
        ui: uiStats,
        sidekiq: sidekiqStats,
        domains_needing: domainsNeeding,
        processed_domains: processedStats,
        audit_logs_count: recentLogs.filter(log => log.service_name === 'domain_testing').length
      };
      
      statSnapshots.push(snapshot);
      auditLogSnapshots.push(recentLogs);
      
      console.log(`📊 Snapshot ${i + 1}/6 at ${new Date().toLocaleTimeString()}`);
      console.log(`   UI DNS Queue: ${uiStats.dns_queue} | Sidekiq DNS Queue: ${sidekiqStats.dns_queue || 'N/A'}`);
      console.log(`   UI Processed: ${uiStats.total_processed} | Sidekiq Processed: ${sidekiqStats.total_processed || 'N/A'}`);
      console.log(`   DNS Not Tested: ${uiStats.dns_not_tested} | Backend Needing: ${domainsNeeding.dns_needed || 'N/A'}`);
      console.log(`   Test Domains Processed: ${processedStats.dns_tested || 0} of ${processedStats.total || 0}`);
      console.log(`   Recent DNS audit logs: ${snapshot.audit_logs_count}`);
      
      // Check for Sidekiq errors
      if (sidekiqStats.error) {
        console.log(`   ⚠️  Sidekiq error: ${sidekiqStats.error}`);
      }
      console.log('');
    }
    
    // Final screenshot
    await page.screenshot({ 
      path: path.join(testResultsDir, 'domain_queue_final.png'),
      fullPage: true 
    });
    
    // Analyze results
    console.log('\n📈 Test Results Analysis:\n');
    
    // Check if we have valid snapshots
    const validSnapshots = statSnapshots.filter(s => s.sidekiq && !s.sidekiq.error);
    if (validSnapshots.length === 0) {
      console.log('❌ No valid Sidekiq data collected. Make sure Sidekiq is running.');
    } else {
      // Check if queue is draining properly
      const firstSnapshot = validSnapshots[0];
      const lastSnapshot = validSnapshots[validSnapshots.length - 1];
      
      console.log('Queue Drainage:');
      console.log(`  Initial DNS queue: ${firstSnapshot.sidekiq.dns_queue}`);
      console.log(`  Final DNS queue: ${lastSnapshot.sidekiq.dns_queue}`);
      console.log(`  Queue reduction: ${firstSnapshot.sidekiq.dns_queue - lastSnapshot.sidekiq.dns_queue}`);
      console.log(`  Domains processed: ${lastSnapshot.sidekiq.total_processed - (initialSidekiq?.total_processed || 0)}`);
      console.log(`  Test domains with DNS results: ${lastSnapshot.processed_domains.dns_tested}`);
      
      // Check UI/Backend consistency
      console.log('\nUI/Backend Consistency:');
      let consistencyIssues = 0;
      validSnapshots.forEach((snapshot, index) => {
        const uiQueue = parseInt(snapshot.ui.dns_queue.replace(/,/g, ''));
        const backendQueue = snapshot.sidekiq.dns_queue;
        const diff = Math.abs(uiQueue - backendQueue);
        if (diff > 2) {
          console.log(`  ❌ Snapshot ${index + 1}: UI shows ${uiQueue}, backend shows ${backendQueue} (diff: ${diff})`);
          consistencyIssues++;
        } else {
          console.log(`  ✅ Snapshot ${index + 1}: UI and backend are consistent (diff: ${diff})`);
        }
      });
      
      // Check SCT audit logs
      console.log('\nSCT Audit Logs:');
      const allAuditLogs = auditLogSnapshots.flat();
      const dnsTestLogs = allAuditLogs.filter(log => 
        log.service_name === 'domain_testing' && 
        log.operation_type === 'test_dns'
      );
      const uniqueDnsLogs = [...new Map(dnsTestLogs.map(log => [log.id, log])).values()];
      console.log(`  Total unique DNS test logs: ${uniqueDnsLogs.length}`);
      console.log(`  Success: ${uniqueDnsLogs.filter(log => log.status === 'success').length}`);
      console.log(`  Failed: ${uniqueDnsLogs.filter(log => log.status === 'failed').length}`);
      console.log(`  Pending: ${uniqueDnsLogs.filter(log => log.status === 'pending').length}`);
      
      // Check follow-up queues
      console.log('\nFollow-up Queue Effects:');
      console.log(`  MX queue growth: ${lastSnapshot.sidekiq.mx_queue - (initialSidekiq?.mx_queue || 0)}`);
      console.log(`  A Record workers in queue: ${lastSnapshot.sidekiq.a_record_workers}`);
      console.log(`  Domains needing MX: ${lastSnapshot.domains_needing.mx_needed}`);
      
      // Final verification
      console.log('\n🎯 Final Verification:');
      const testPassed = consistencyIssues === 0 && uniqueDnsLogs.length > 0;
      if (testPassed) {
        console.log('✅ All tests passed! Queue processing and stats are working correctly.');
      } else {
        console.log('❌ Test failed! Issues detected:');
        if (consistencyIssues > 0) {
          console.log(`  - ${consistencyIssues} UI/Backend consistency issues`);
        }
        if (uniqueDnsLogs.length === 0) {
          console.log('  - No DNS test audit logs created');
        }
      }
      
      // Save results
      const results = {
        test_run: new Date().toISOString(),
        domains_created: domainIds.length,
        snapshots: statSnapshots,
        audit_logs_summary: {
          total_unique: uniqueDnsLogs.length,
          success: uniqueDnsLogs.filter(log => log.status === 'success').length,
          failed: uniqueDnsLogs.filter(log => log.status === 'failed').length,
          sample_logs: uniqueDnsLogs.slice(0, 5)
        },
        consistency_issues: consistencyIssues,
        test_passed: testPassed
      };
      
      fs.writeFileSync(
        path.join(testResultsDir, 'domain_queue_results.json'),
        JSON.stringify(results, null, 2)
      );
      console.log(`\n📄 Detailed results saved to ${path.join(testResultsDir, 'domain_queue_results.json')}`);
    }
    
  } catch (error) {
    console.error('❌ Test failed with error:', error.message);
    await page.screenshot({ 
      path: path.join(testResultsDir, 'domain_queue_error.png'),
      fullPage: true 
    });
  } finally {
    // Clean up test domains
    console.log('\n🧹 Cleaning up test domains...');
    const finalCleanup = runRailsHelper('cleanup');
    if (finalCleanup) {
      console.log(`Cleaned up ${finalCleanup.deleted_count} test domains`);
    }
    
    await browser.close();
    console.log('✅ Test completed');
  }
}

// Run the test
runTest().catch(console.error);