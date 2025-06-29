const puppeteer = require('puppeteer');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Helper to run Rails commands via temporary files
function runRailsScript(scriptContent) {
  const tempFile = path.join('/tmp', `rails_script_${Date.now()}.rb`);
  try {
    fs.writeFileSync(tempFile, scriptContent);
    const output = execSync(`bundle exec rails runner ${tempFile} 2>/dev/null`, {
      encoding: 'utf8',
      cwd: '/Users/benjamin/Documents/Projects/b2b',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return output.trim();
  } catch (error) {
    console.error(`Rails script failed:`, error.message);
    console.error(`Script content:`, scriptContent);
    throw error;
  } finally {
    if (fs.existsSync(tempFile)) {
      fs.unlinkSync(tempFile);
    }
  }
}

// Helper to get Sidekiq queue stats
function getSidekiqStats() {
  const script = `
begin
  require 'sidekiq/api'
  stats = {}
  stats[:dns_queue] = Sidekiq::Queue.new('domain_dns_testing').size
  stats[:mx_queue] = Sidekiq::Queue.new('domain_mx_testing').size
  stats[:default_queue] = Sidekiq::Queue.new('default').size

  # Count specific workers in default queue
  default_queue = Sidekiq::Queue.new('default')
  stats[:a_record_workers] = default_queue.count { |job| job.klass == 'DomainARecordTestingWorker' }
  stats[:web_content_workers] = default_queue.count { |job| job.klass == 'DomainWebContentExtractionWorker' }

  stats[:total_enqueued] = Sidekiq::Stats.new.enqueued
  stats[:total_processed] = Sidekiq::Stats.new.processed
  puts stats.to_json
rescue => e
  # Return default stats if Sidekiq is not available
  puts({ dns_queue: 0, mx_queue: 0, default_queue: 0, a_record_workers: 0, 
         web_content_workers: 0, total_enqueued: 0, total_processed: 0, 
         error: e.message }.to_json)
end
  `;
  return JSON.parse(runRailsScript(script));
}

// Helper to get SCT audit logs
function getRecentAuditLogs(limit = 10) {
  const script = `
logs = ServiceAuditLog.order(created_at: :desc).limit(${limit})
result = logs.map do |log|
  {
    id: log.id,
    service_name: log.service_name,
    operation_type: log.operation_type,
    status: log.status,
    auditable_type: log.auditable_type,
    auditable_id: log.auditable_id,
    created_at: log.created_at.iso8601,
    execution_time_ms: log.execution_time_ms
  }
end
puts result.to_json
  `;
  return JSON.parse(runRailsScript(script));
}

// Helper to create test domains
function createTestDomains(count) {
  const script = `
domains = []
${count}.times do |i|
  domain = Domain.create!(
    domain: "test-domain-#{Time.current.to_i}-#{i}.com",
    dns: nil,
    mx: nil,
    www: nil
  )
  domains << domain.id
end
puts domains.to_json
  `;
  return JSON.parse(runRailsScript(script));
}

// Helper to get domains needing service
function getDomainsNeedingService() {
  const script = `
stats = {
  dns_needed: Domain.needing_service('domain_testing').count,
  mx_needed: Domain.needing_service('domain_mx_testing').count,
  a_record_needed: Domain.needing_service('domain_a_record_testing').count,
  web_content_needed: Domain.needing_service('domain_web_content_extraction').count
}
puts stats.to_json
  `;
  return JSON.parse(runRailsScript(script));
}

// Helper to get processed domain stats
function getProcessedDomainStats() {
  const script = `
test_domains = Domain.where("domain LIKE ?", "test-domain-%")
stats = {
  total: test_domains.count,
  dns_tested: test_domains.where.not(dns: nil).count,
  dns_active: test_domains.where(dns: true).count,
  mx_tested: test_domains.where.not(mx: nil).count,
  www_tested: test_domains.where.not(www: nil).count
}
puts stats.to_json
  `;
  return JSON.parse(runRailsScript(script));
}

async function runTest() {
  console.log('🚀 Starting Domain Queue Integration Test\n');
  
  // Clean up any existing test domains first
  console.log('🧹 Cleaning up any existing test domains...');
  try {
    const cleanupScript = `
deleted = Domain.where("domain LIKE ?", "test-domain-%").destroy_all
puts "Deleted #{deleted.count} existing test domains"
    `;
    const cleanupResult = runRailsScript(cleanupScript);
    console.log(cleanupResult);
  } catch (error) {
    console.log('No existing test domains to clean up');
  }
  
  // Create test domains
  console.log('\n📝 Creating 50 test domains...');
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
    await page.waitForSelector('[data-stat="domain_dns_testing"]', { timeout: 10000 });
    
    // Wait for initial stats to load
    await page.waitForTimeout(2000);
    
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
    
    // Find the DNS testing card and input
    const dnsCountInput = await page.$('[data-service="domain_testing"] input[type="number"]');
    if (!dnsCountInput) {
      throw new Error('DNS testing count input not found');
    }
    
    // Clear and type the count
    await dnsCountInput.click({ clickCount: 3 }); // Triple click to select all
    await page.keyboard.press('Backspace');
    await dnsCountInput.type('50');
    
    // Find and click the submit button
    const submitButton = await page.$('[data-service="domain_testing"] button[type="submit"]');
    if (!submitButton) {
      throw new Error('DNS testing submit button not found');
    }
    await submitButton.click();
    
    // Wait for success indication
    await page.waitForTimeout(3000);
    console.log('✅ Queue request submitted\n');
    
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
      const processedStats = getProcessedDomainStats();
      const recentLogs = getRecentAuditLogs(10);
      
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
      console.log(`   UI DNS Queue: ${uiStats.dns_queue} | Sidekiq DNS Queue: ${sidekiqStats.dns_queue}`);
      console.log(`   UI Processed: ${uiStats.total_processed} | Sidekiq Processed: ${sidekiqStats.total_processed}`);
      console.log(`   DNS Not Tested: ${uiStats.dns_not_tested} | Backend Needing: ${domainsNeeding.dns_needed}`);
      console.log(`   Test Domains Processed: ${processedStats.dns_tested} of ${processedStats.total}`);
      console.log(`   Recent DNS audit logs: ${snapshot.audit_logs_count}`);
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
    console.log(`  Queue reduction: ${firstSnapshot.sidekiq.dns_queue - lastSnapshot.sidekiq.dns_queue}`);
    console.log(`  Domains processed: ${lastSnapshot.sidekiq.total_processed - initialSidekiq.total_processed}`);
    console.log(`  Test domains with DNS results: ${lastSnapshot.processed_domains.dns_tested}`);
    
    // Check UI/Backend consistency
    console.log('\nUI/Backend Consistency:');
    let consistencyIssues = 0;
    statSnapshots.forEach((snapshot, index) => {
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
    console.log(`  MX queue growth: ${lastSnapshot.sidekiq.mx_queue - initialSidekiq.mx_queue}`);
    console.log(`  A Record workers in queue: ${lastSnapshot.sidekiq.a_record_workers}`);
    console.log(`  Domains needing MX: ${lastSnapshot.domains_needing.mx_needed}`);
    console.log(`  Domains needing A Record: ${lastSnapshot.domains_needing.a_record_needed}`);
    
    // Queue drainage analysis
    console.log('\nQueue Drainage Analysis:');
    const queueDrainageRate = statSnapshots.map((snapshot, index) => {
      if (index === 0) return 0;
      const prevQueue = statSnapshots[index - 1].sidekiq.dns_queue;
      const currQueue = snapshot.sidekiq.dns_queue;
      return prevQueue - currQueue;
    }).slice(1);
    console.log(`  Average drainage rate: ${(queueDrainageRate.reduce((a, b) => a + b, 0) / queueDrainageRate.length).toFixed(1)} domains per 5 seconds`);
    console.log(`  Max drainage: ${Math.max(...queueDrainageRate)} domains in 5 seconds`);
    
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
    
    // Save detailed results
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
      queue_drainage_rate: queueDrainageRate,
      test_passed: testPassed
    };
    
    fs.writeFileSync(
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
    try {
      const cleanupScript = `
deleted = Domain.where("domain LIKE ?", "test-domain-%").destroy_all
puts "Cleaned up #{deleted.count} test domains"
      `;
      const cleanupResult = runRailsScript(cleanupScript);
      console.log(cleanupResult);
    } catch (error) {
      console.error('Failed to clean up test domains:', error.message);
    }
    
    await browser.close();
    console.log('✅ Test completed');
  }
}

// Create test results directory
fs.mkdirSync('test_results', { recursive: true });

// Run the test
runTest().catch(console.error);