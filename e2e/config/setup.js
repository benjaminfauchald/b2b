/**
 * Jest Setup File
 * 
 * This file runs once before all tests. It sets up global configuration,
 * extends Jest with custom matchers, and configures error handling.
 * 
 * Senior Developer Note: Setup files are where you establish the "contract"
 * between your test framework and your application.
 */

// Extend Jest with Puppeteer-specific matchers
require('expect-puppeteer');

// Global test configuration
const TEST_CONFIG = {
  baseUrl: process.env.BASE_URL || 'https://local.connectica.no',
  testUser: {
    email: 'test@test.no',
    password: 'CodemyFTW2'
  },
  adminUser: {
    email: 'admin@example.com', 
    password: 'CodemyFTW2'
  },
  timeouts: {
    navigation: 30000,
    element: 10000,
    api: 15000
  }
};

// Make config globally available
global.TEST_CONFIG = TEST_CONFIG;

// Enhanced error handling for better debugging
const originalIt = global.it;
global.it = (name, fn, timeout) => {
  return originalIt(name, async () => {
    try {
      await fn();
    } catch (error) {
      // Capture screenshot on test failure
      if (global.page && typeof global.page.screenshot === 'function') {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const screenshotPath = `screenshots/failure-${name.replace(/\s+/g, '-')}-${timestamp}.png`;
        
        try {
          await global.page.screenshot({ 
            path: screenshotPath, 
            fullPage: true 
          });
          console.log(`💔 Test failed. Screenshot saved: ${screenshotPath}`);
        } catch (screenshotError) {
          console.log('Failed to capture screenshot:', screenshotError.message);
        }
      }
      
      // Enhanced error context
      console.error(`
🚨 Test Failure: ${name}
📍 URL: ${global.page ? await global.page.url() : 'Unknown'}
⏰ Timestamp: ${new Date().toISOString()}
💥 Error: ${error.message}
      `);
      
      throw error;
    }
  }, timeout);
};

// Setup page defaults for each test
beforeEach(async () => {
  // Configure page defaults (Jest-Puppeteer provides the page)
  if (global.page) {
    // Set viewport for consistent behavior
    await global.page.setViewport({ width: 1920, height: 1080 });
    
    // Set reasonable timeouts
    global.page.setDefaultNavigationTimeout(TEST_CONFIG.timeouts.navigation);
    global.page.setDefaultTimeout(TEST_CONFIG.timeouts.element);
    
    // Log page errors for debugging
    global.page.on('pageerror', error => {
      console.error('🔥 Page Error:', error.message);
    });
    
    // Log failed requests
    global.page.on('requestfailed', request => {
      console.error('🌐 Request Failed:', request.url(), request.failure().errorText);
    });
  }
});

console.log('🚀 E2E Test Environment Ready');
console.log(`📍 Base URL: ${TEST_CONFIG.baseUrl}`);
console.log(`🏃 Running in ${process.env.CI ? 'CI' : 'Development'} mode`);