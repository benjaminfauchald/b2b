/**
 * Base Page Object
 * 
 * This is the foundation class that all page objects inherit from.
 * It provides common functionality that every page needs.
 * 
 * Senior Developer Note: The base page pattern prevents code duplication
 * and ensures consistent behavior across all page objects.
 */

class BasePage {
  constructor(page) {
    this.page = page;
    this.timeout = global.TEST_CONFIG.timeouts.element;
  }

  /**
   * Navigate to a specific URL
   * @param {string} url - The URL to navigate to
   */
  async navigateTo(url) {
    await this.page.goto(url, { 
      waitUntil: 'networkidle0',
      timeout: global.TEST_CONFIG.timeouts.navigation 
    });
  }

  /**
   * Wait for an element to be visible
   * @param {string} selector - CSS selector for the element
   * @param {number} timeout - Optional timeout override
   */
  async waitForElement(selector, timeout = this.timeout) {
    return await this.page.waitForSelector(selector, { 
      visible: true, 
      timeout 
    });
  }

  /**
   * Wait for an element to disappear
   * @param {string} selector - CSS selector for the element
   */
  async waitForElementToDisappear(selector) {
    return await this.page.waitForSelector(selector, { 
      hidden: true, 
      timeout: this.timeout 
    });
  }

  /**
   * Click an element with built-in waiting
   * @param {string} selector - CSS selector for the element
   */
  async clickElement(selector) {
    await this.waitForElement(selector);
    await this.page.click(selector);
  }

  /**
   * Fill a form field with built-in waiting
   * @param {string} selector - CSS selector for the input
   * @param {string} value - Value to fill
   */
  async fillField(selector, value) {
    await this.waitForElement(selector);
    // Clear the field first, then type the new value
    await this.page.focus(selector);
    await this.page.keyboard.down('Control');
    await this.page.keyboard.press('a');
    await this.page.keyboard.up('Control');
    await this.page.type(selector, value);
  }

  /**
   * Get text content from an element
   * @param {string} selector - CSS selector for the element
   */
  async getTextContent(selector) {
    await this.waitForElement(selector);
    // Use $eval for getting text content in newer Puppeteer
    return await this.page.$eval(selector, el => el.textContent);
  }

  /**
   * Check if an element is visible
   * @param {string} selector - CSS selector for the element
   */
  async isElementVisible(selector) {
    try {
      const element = await this.page.$(selector);
      if (!element) return false;
      // Use boundingBox to check visibility in newer Puppeteer
      const box = await element.boundingBox();
      return box !== null;
    } catch (error) {
      return false;
    }
  }

  /**
   * Wait for page navigation to complete
   */
  async waitForNavigation() {
    await this.page.waitForNavigation({ 
      waitUntil: 'networkidle0',
      timeout: global.TEST_CONFIG.timeouts.navigation 
    });
  }

  /**
   * Take a screenshot for debugging
   * @param {string} name - Name for the screenshot file
   */
  async takeScreenshot(name) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const path = `screenshots/${name}-${timestamp}.png`;
    await this.page.screenshot({ path, fullPage: true });
    console.log(`📸 Screenshot saved: ${path}`);
    return path;
  }
}

module.exports = BasePage;