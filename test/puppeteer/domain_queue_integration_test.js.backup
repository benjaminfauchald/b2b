const puppeteer = require('puppeteer');
const { execSync } = require('child_process');

// Helper to run Rails commands
function runRailsCommand(command) {
  try {
    const output = execSync(`bundle exec rails runner "${command}"`, {
      encoding: 'utf8',
      cwd: '/Users/benjamin/Documents/Projects/b2b'
    });
    return output.trim();
  } catch (error) {
    console.error(`Rails command failed: ${command}`, error.message);
    throw error;
  }
}

// Helper to get Sidekiq queue stats
function getSidekiqStats() {
  const command = `
    require 'sidekiq/api'
    stats = {}
    stats[:dns_queue] = Sidekiq::Queue.new('domain_dns_testing').size
    stats[:mx_queue] = Sidekiq::Queue.new('domain_mx_testing').size
    stats[:default_queue] = Sidekiq::Queue.new('default').size
    stats[:total_enqueued] = Sidekiq::Stats.new.enqueued
    stats[:total_processed] = Sidekiq::Stats.new.processed
    puts stats.to_json
  `;
  return JSON.parse(runRailsCommand(command));
}

// Helper to get SCT audit logs
function getRecentAuditLogs(limit = 10) {
  const command = `
    logs = ServiceAuditLog.order(created_at: :desc).limit(${limit})
    result = logs.map do |log|
      {
        id: log.id,
        service_name: log.service_name,
        operation_type: log.operation_type,
        status: log.status,
        auditable_type: log.auditable_type,
        auditable_id: log.auditable_id,
        created_at: log.created_at.iso8601
      }
    end
    puts result.to_json
  `;
  return JSON.parse(runRailsCommand(command));
}

// Helper to create test domains
function createTestDomains(count) {
  const command = `
    domains = []
    ${count}.times do |i|
      domain = Domain.create!(
        domain: "test-domain-#{Time.current.to_i}-#{i}.com"
      )
      domains << domain.id
    end
    puts domains.to_json
  `;
  return JSON.parse(runRailsCommand(command));
}

// Helper to get domains needing service
function getDomainsNeedingService() {
  const command = `
    stats = {
      dns_needed: Domain.needing_service('domain_testing').count,
      mx_needed: Domain.needing_service('domain_mx_testing').count,
      a_record_needed: Domain.needing_service('domain_a_record_testing').count,
      web_content_needed: Domain.needing_service('domain_web_content_extraction').count
    }
    puts stats.to_json
  `;
  return JSON.parse(runRailsCommand(command));
}

async function runTest() {
  console.log('🚀 Starting Domain Queue Integration Test\n');
  
  // Create test domains
  console.log('📝 Creating 50 test domains...');
  const domainIds = createTestDomains(50);
  console.log(`✅ Created ${domainIds.length} test domains\n`);
  
  // Check initial stats
  console.log('📊 Initial Statistics:');
  const initialSidekiq = getSidekiqStats();
  const initialDomainsNeeding = getDomainsNeedingService();
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
    await page.waitForSelector('[data-stat="domain_dns_testing"]');
    
    // Take initial screenshot
    await page.screenshot({ 
      path: 'test_results/domain_queue_initial.png',
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
    
    // Find the DNS testing form and input
    const dnsForm = await page.$('[data-service="domain_testing"] form');
    if (!dnsForm) {
      throw new Error('DNS testing form not found');
    }
    
    // Clear and type the count
    const countInput = await page.$('[data-service="domain_testing"] input[type="number"]');
    await countInput.click({ clickCount: 3 }); // Triple click to select all
    await page.keyboard.press('Backspace');
    await countInput.type('50');
    
    // Click the queue button
    await page.click('[data-service="domain_testing"] button[type="submit"]');
    
    // Wait for the success toast
    await page.waitForSelector('.bg-green-500', { timeout: 5000 });
    console.log('✅ Successfully queued 50 domains\n');
    
    // Take screenshot after queueing
    await page.screenshot({ 
      path: 'test_results/domain_queue_after_queue.png',
      fullPage: true 
    });
    
    // Monitor stats for 30 seconds
    console.log('📊 Monitoring statistics for 30 seconds...\n');
    const statSnapshots = [];
    const auditLogSnapshots = [];
    
    for (let i = 0; i < 6; i++) {
      await page.waitForTimeout(5000); // Wait 5 seconds
      
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
      const sidekiqStats = getSidekiqStats();
      const domainsNeeding = getDomainsNeedingService();
      const recentLogs = getRecentAuditLogs(5);
      
      const snapshot = {
        time: new Date().toISOString(),
        ui: uiStats,
        sidekiq: sidekiqStats,
        domains_needing: domainsNeeding,
        audit_logs_count: recentLogs.length
      };
      
      statSnapshots.push(snapshot);
      auditLogSnapshots.push(recentLogs);
      
      console.log(`📊 Snapshot ${i + 1}/6 at ${new Date().toLocaleTimeString()}`);
      console.log(`   UI DNS Queue: ${uiStats.dns_queue} | Sidekiq DNS Queue: ${sidekiqStats.dns_queue}`);
      console.log(`   UI Processed: ${uiStats.total_processed} | Sidekiq Processed: ${sidekiqStats.total_processed}`);
      console.log(`   DNS Not Tested: ${uiStats.dns_not_tested} | Backend Needing: ${domainsNeeding.dns_needed}`);
      console.log(`   Recent audit logs: ${recentLogs.filter(log => log.service_name === 'domain_testing').length} DNS tests`);
      console.log('');
    }
    
    // Final screenshot
    await page.screenshot({ 
      path: 'test_results/domain_queue_final.png',
      fullPage: true 
    });
    
    // Analyze results
    console.log('\n📈 Test Results Analysis:\n');
    
    // Check if queue is draining properly
    const firstSnapshot = statSnapshots[0];
    const lastSnapshot = statSnapshots[statSnapshots.length - 1];
    
    console.log('Queue Drainage:');
    console.log(`  Initial DNS queue: ${firstSnapshot.sidekiq.dns_queue}`);
    console.log(`  Final DNS queue: ${lastSnapshot.sidekiq.dns_queue}`);
    console.log(`  Domains processed: ${lastSnapshot.sidekiq.total_processed - initialSidekiq.total_processed}`);
    
    // Check UI/Backend consistency
    console.log('\nUI/Backend Consistency:');
    let consistencyIssues = 0;
    statSnapshots.forEach((snapshot, index) => {
      const uiQueue = parseInt(snapshot.ui.dns_queue.replace(/,/g, ''));
      const backendQueue = snapshot.sidekiq.dns_queue;
      if (Math.abs(uiQueue - backendQueue) > 2) {
        console.log(`  ❌ Snapshot ${index + 1}: UI shows ${uiQueue}, backend shows ${backendQueue}`);
        consistencyIssues++;
      } else {
        console.log(`  ✅ Snapshot ${index + 1}: UI and backend are consistent`);
      }
    });
    
    // Check SCT audit logs
    console.log('\nSCT Audit Logs:');
    const allAuditLogs = auditLogSnapshots.flat();
    const dnsTestLogs = allAuditLogs.filter(log => 
      log.service_name === 'domain_testing' && 
      log.operation_type === 'test_dns'
    );
    console.log(`  Total DNS test logs created: ${dnsTestLogs.length}`);
    console.log(`  Success: ${dnsTestLogs.filter(log => log.status === 'success').length}`);
    console.log(`  Failed: ${dnsTestLogs.filter(log => log.status === 'failed').length}`);
    console.log(`  Pending: ${dnsTestLogs.filter(log => log.status === 'pending').length}`);
    
    // Check follow-up queues
    console.log('\nFollow-up Queue Effects:');
    console.log(`  MX queue growth: ${lastSnapshot.sidekiq.mx_queue - initialSidekiq.mx_queue}`);
    console.log(`  Domains needing MX: ${lastSnapshot.domains_needing.mx_needed}`);
    
    // Final verification
    console.log('\n🎯 Final Verification:');
    const testPassed = consistencyIssues === 0 && dnsTestLogs.length > 0;
    if (testPassed) {
      console.log('✅ All tests passed! Queue processing and stats are working correctly.');
    } else {
      console.log('❌ Test failed! Issues detected with queue processing or stat updates.');
    }
    
    // Save detailed results
    const results = {
      test_run: new Date().toISOString(),
      domains_created: domainIds.length,
      snapshots: statSnapshots,
      audit_logs: dnsTestLogs.slice(0, 10), // First 10 logs
      consistency_issues: consistencyIssues,
      test_passed: testPassed
    };
    
    require('fs').writeFileSync(
      'test_results/domain_queue_results.json',
      JSON.stringify(results, null, 2)
    );
    console.log('\n📄 Detailed results saved to test_results/domain_queue_results.json');
    
  } catch (error) {
    console.error('❌ Test failed with error:', error.message);
    await page.screenshot({ 
      path: 'test_results/domain_queue_error.png',
      fullPage: true 
    });
  } finally {
    // Clean up test domains
    console.log('\n🧹 Cleaning up test domains...');
    const cleanup = `Domain.where("domain LIKE ?", "test-domain-%").destroy_all`;
    runRailsCommand(cleanup);
    
    await browser.close();
    console.log('✅ Test completed');
  }
}

// Create test results directory
require('fs').mkdirSync('test_results', { recursive: true });

// Run the test
runTest().catch(console.error);