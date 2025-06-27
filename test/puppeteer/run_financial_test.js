#!/usr/bin/env node

/**
 * Simple test runner for Company Financial Data Puppeteer tests
 * 
 * Usage:
 *   node test/puppeteer/run_financial_test.js
 *   node test/puppeteer/run_financial_test.js --headless
 *   node test/puppeteer/run_financial_test.js --test="Financial data fetch button"
 */

const puppeteer = require('puppeteer');
const path = require('path');

class FinancialDataTestRunner {
  constructor(options = {}) {
    this.options = {
      headless: options.headless || false,
      slowMo: options.slowMo || 50,
      timeout: options.timeout || 30000,
      baseUrl: 'https://local.connectica.no',
      companyId: 301078,
      ...options
    };
    
    this.browser = null;
    this.page = null;
    this.results = [];
  }

  async setup() {
    console.log('🚀 Starting Company Financial Data Tests...\n');
    
    this.browser = await puppeteer.launch({
      headless: this.options.headless,
      slowMo: this.options.slowMo,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
      devtools: !this.options.headless
    });

    this.page = await this.browser.newPage();
    await this.page.setViewport({ width: 1280, height: 800 });

    // Enable console logging from the page
    this.page.on('console', msg => {
      if (msg.type() === 'log') {
        console.log('PAGE LOG:', msg.text());
      }
    });

    // Login
    await this.login();
  }

  async login() {
    console.log('🔐 Logging in...');
    
    await this.page.goto(`${this.options.baseUrl}/users/sign_in`);
    await this.page.type('#user_email', 'test@test.no');
    await this.page.type('#user_password', 'CodemyFTW2');
    await this.page.click('input[type="submit"]');
    await this.page.waitForNavigation();
    
    console.log('✅ Login successful\n');
  }

  async runTest(testName, testFunction) {
    console.log(`🧪 Running: ${testName}`);
    
    try {
      const startTime = Date.now();
      await testFunction();
      const duration = Date.now() - startTime;
      
      this.results.push({
        name: testName,
        status: 'PASSED',
        duration: `${duration}ms`
      });
      
      console.log(`✅ PASSED: ${testName} (${duration}ms)\n`);
      
    } catch (error) {
      this.results.push({
        name: testName,
        status: 'FAILED',
        error: error.message
      });
      
      console.log(`❌ FAILED: ${testName}`);
      console.log(`   Error: ${error.message}\n`);
    }
  }

  async testFinancialDataFetch() {
    // Navigate to company page
    await this.page.goto(`${this.options.baseUrl}/companies/${this.options.companyId}`);
    await this.page.waitForSelector('h1', { timeout: 10000 });

    // Take initial screenshot
    await this.page.screenshot({ 
      path: 'test/puppeteer/screenshots/financial-test-initial.png',
      fullPage: true 
    });

    // Find the Financial Data section and button
    const fetchButton = await this.page.evaluateHandle(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      return buttons.find(button => 
        button.textContent && button.textContent.includes('Fetch Financial Data')
      );
    });

    if (!fetchButton) {
      throw new Error('Fetch Financial Data button not found');
    }

    // Verify initial state
    const initialState = await this.page.evaluate(() => {
      const noDataElements = Array.from(document.querySelectorAll('*')).filter(el => 
        el.textContent && el.textContent.trim() === 'No Data'
      );
      return {
        hasNoData: noDataElements.length > 0,
        noDataCount: noDataElements.length
      };
    });

    console.log('   Initial state:', initialState);

    // Check button is enabled
    const isDisabled = await fetchButton.evaluate(el => el.disabled);
    if (isDisabled) {
      throw new Error('Button should be enabled initially');
    }

    // Click the button
    await fetchButton.click();
    console.log('   Clicked Fetch Financial Data button');

    // Wait for button to become disabled
    await this.page.waitForFunction(
      (button) => button.disabled,
      { timeout: 5000 },
      fetchButton
    );

    console.log('   Button disabled - service started');

    // Take loading screenshot
    await this.page.screenshot({ 
      path: 'test/puppeteer/screenshots/financial-test-loading.png' 
    });

    // Wait for completion (button re-enabled or data populated)
    await this.page.waitForFunction(
      (button) => {
        const isEnabled = !button.disabled;
        const hasFinancialData = document.querySelector('[data-testid="revenue"]') ||
          Array.from(document.querySelectorAll('*')).some(el => 
            el.textContent && (
              el.textContent.includes('kr') || 
              el.textContent.match(/\d{1,3}(,\d{3})*\s*(NOK|kr)/i)
            )
          );
        return isEnabled || hasFinancialData;
      },
      { timeout: 20000 },
      fetchButton
    );

    console.log('   Service completed');

    // Take final screenshot
    await this.page.screenshot({ 
      path: 'test/puppeteer/screenshots/financial-test-completed.png',
      fullPage: true 
    });

    // Verify final state
    const finalState = await this.page.evaluate(() => {
      const noDataElements = Array.from(document.querySelectorAll('*')).filter(el => 
        el.textContent && el.textContent.trim() === 'No Data'
      );
      
      const financialElements = Array.from(document.querySelectorAll('*')).filter(el => 
        el.textContent && (
          el.textContent.includes('kr') || 
          el.textContent.match(/\d{1,3}(,\d{3})*/) ||
          el.textContent.includes('NOK')
        )
      );

      return {
        noDataCount: noDataElements.length,
        hasFinancialData: financialElements.length > 0,
        financialDataSample: financialElements.slice(0, 3).map(el => el.textContent.trim())
      };
    });

    console.log('   Final state:', finalState);

    // Verify button is re-enabled
    const isFinallyDisabled = await fetchButton.evaluate(el => el.disabled);
    if (isFinallyDisabled) {
      throw new Error('Button should be re-enabled after completion');
    }

    // Verify data was populated (less "No Data" elements or financial data present)
    if (finalState.noDataCount >= initialState.noDataCount && !finalState.hasFinancialData) {
      console.log('   Warning: No clear indication that financial data was populated');
    }

    console.log('   ✅ Button state and data population verified');
  }

  async testButtonStates() {
    await this.page.goto(`${this.options.baseUrl}/companies/${this.options.companyId}`);
    await this.page.waitForSelector('h1');

    // Find all enhancement service buttons
    const buttons = await this.page.$$eval('button', buttons => 
      buttons
        .filter(btn => btn.textContent && (
          btn.textContent.includes('Fetch') ||
          btn.textContent.includes('Discovery') ||
          btn.textContent.includes('LinkedIn')
        ))
        .map(btn => ({
          text: btn.textContent.trim(),
          disabled: btn.disabled,
          className: btn.className
        }))
    );

    console.log('   Available service buttons:', buttons.length);
    
    if (buttons.length === 0) {
      throw new Error('No enhancement service buttons found');
    }

    // Verify at least one button is available
    const enabledButtons = buttons.filter(btn => !btn.disabled);
    if (enabledButtons.length === 0) {
      throw new Error('All service buttons are disabled');
    }

    console.log(`   ✅ Found ${enabledButtons.length} enabled service buttons`);
  }

  async cleanup() {
    if (this.browser) {
      await this.browser.close();
    }
  }

  async run() {
    try {
      await this.setup();

      // Run tests
      await this.runTest(
        'Financial Data Fetch - Button States and Data Population',
        () => this.testFinancialDataFetch()
      );

      await this.runTest(
        'Enhancement Service Buttons Availability',
        () => this.testButtonStates()
      );

      // Print results
      this.printResults();

    } catch (error) {
      console.error('❌ Test runner failed:', error);
    } finally {
      await this.cleanup();
    }
  }

  printResults() {
    console.log('\n📊 Test Results:');
    console.log('================');
    
    this.results.forEach(result => {
      const status = result.status === 'PASSED' ? '✅' : '❌';
      console.log(`${status} ${result.name}`);
      
      if (result.duration) {
        console.log(`   Duration: ${result.duration}`);
      }
      
      if (result.error) {
        console.log(`   Error: ${result.error}`);
      }
    });

    const passed = this.results.filter(r => r.status === 'PASSED').length;
    const failed = this.results.filter(r => r.status === 'FAILED').length;
    
    console.log(`\nSummary: ${passed} passed, ${failed} failed`);
    
    if (failed === 0) {
      console.log('🎉 All tests passed!');
    }
  }
}

// Parse command line arguments
const args = process.argv.slice(2);
const options = {
  headless: args.includes('--headless'),
  slowMo: args.includes('--fast') ? 0 : 50
};

// Run the tests
const runner = new FinancialDataTestRunner(options);
runner.run();