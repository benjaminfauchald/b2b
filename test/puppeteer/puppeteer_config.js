/**
 * Common Puppeteer Configuration for all tests
 * This file provides consistent browser settings across all Puppeteer tests
 * with larger viewport sizes for better full-page screenshots
 */

const PUPPETEER_CONFIG = {
  // Browser launch options
  launch: {
    headless: false,
    defaultViewport: { width: 1920, height: 1080 }, // Full HD resolution
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-accelerated-2d-canvas',
      '--disable-gpu',
      '--window-size=1920,1080', // Ensure window size matches viewport
      '--start-maximized',        // Start with maximized window
      '--disable-web-security',   // For local development
      '--disable-features=VizDisplayCompositor'
    ]
  },
  
  // Page viewport settings
  viewport: {
    width: 1920,
    height: 1080,
    deviceScaleFactor: 1
  },
  
  // Screenshot options for full page capture
  screenshot: {
    fullPage: true,
    quality: 90, // JPEG quality (1-100)
    type: 'png'  // Default to PNG for better quality
  },
  
  // Common wait times
  timeouts: {
    navigation: 30000,    // 30 seconds for navigation
    element: 10000,       // 10 seconds for element waiting
    screenshot: 5000      // 5 seconds before taking screenshot
  }
};

// Helper function to create a page with standard settings
async function createConfiguredPage(browser) {
  const page = await browser.newPage();
  await page.setViewport(PUPPETEER_CONFIG.viewport);
  
  // Set longer timeouts
  page.setDefaultNavigationTimeout(PUPPETEER_CONFIG.timeouts.navigation);
  page.setDefaultTimeout(PUPPETEER_CONFIG.timeouts.element);
  
  return page;
}

// Helper function to take a standardized screenshot
async function takeStandardScreenshot(page, path, options = {}) {
  const screenshotOptions = {
    ...PUPPETEER_CONFIG.screenshot,
    path,
    ...options
  };
  
  // Wait a moment for any animations to settle
  await new Promise(resolve => setTimeout(resolve, PUPPETEER_CONFIG.timeouts.screenshot));
  
  return await page.screenshot(screenshotOptions);
}

module.exports = {
  PUPPETEER_CONFIG,
  createConfiguredPage,
  takeStandardScreenshot
};