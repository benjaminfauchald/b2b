/**
 * Jest-Puppeteer Configuration
 * 
 * This configuration ensures consistent browser behavior across all tests.
 * Key principle: Tests should behave identically in development and CI.
 */

module.exports = {
  launch: {
    // Run headless in CI, visible in development for debugging
    headless: process.env.CI === 'true' || process.env.HEADLESS === 'true',
    
    // Browser arguments for stability and performance
    args: [
      '--no-sandbox',                    // Required for CI environments
      '--disable-setuid-sandbox',       // Required for CI environments
      '--disable-dev-shm-usage',        // Prevents memory issues in Docker
      '--disable-accelerated-2d-canvas',
      '--disable-gpu',
      '--window-size=1920,1080',        // Match viewport size
      '--disable-web-security',         // For local development only
      '--disable-features=VizDisplayCompositor'
    ],
    
    // Longer timeout for slower CI environments
    timeout: process.env.CI === 'true' ? 60000 : 30000,
    
    // Don't close browser between tests - we'll manage pages manually
    ignoreDefaultArgs: ['--disable-extensions']
  },
  
  // Browser context options
  browserContext: 'default'
};