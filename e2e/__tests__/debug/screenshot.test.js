/**
 * Debug Test - Take Screenshot
 * 
 * This test helps us see what the actual login page looks like
 * so we can fix our selectors.
 */

describe('Debug - Screenshot Login Page', () => {
  test('should take screenshot of login page', async () => {
    console.log('📸 Taking screenshot of login page');
    
    // Navigate to login page
    await page.goto('https://local.connectica.no/users/sign_in', { 
      waitUntil: 'networkidle0',
      timeout: 30000 
    });
    
    // Take screenshot
    await page.screenshot({ 
      path: '/Users/benjamin/Documents/Projects/b2b/e2e/screenshots/debug-login-page.png',
      fullPage: true 
    });
    
    // Get page content to see the HTML structure
    const content = await page.content();
    console.log('📄 Page title:', await page.title());
    console.log('📍 Page URL:', page.url());
    
    // Check for form elements
    const emailField = await page.$('input[type="email"]');
    const passwordField = await page.$('input[type="password"]');
    const submitButton = await page.$('button[type="submit"]');
    
    console.log('📋 Form elements found:');
    console.log('  Email field:', !!emailField);
    console.log('  Password field:', !!passwordField);
    console.log('  Submit button:', !!submitButton);
    
    // Get all input fields
    const inputs = await page.$$eval('input', inputs => 
      inputs.map(input => ({
        type: input.type,
        name: input.name,
        id: input.id,
        placeholder: input.placeholder,
        className: input.className
      }))
    );
    
    console.log('📝 All input fields:', JSON.stringify(inputs, null, 2));
    
    // Get all buttons
    const buttons = await page.$$eval('button', buttons => 
      buttons.map(button => ({
        type: button.type,
        textContent: button.textContent.trim(),
        className: button.className
      }))
    );
    
    console.log('🔘 All buttons:', JSON.stringify(buttons, null, 2));
    
    expect(true).toBe(true); // Always pass
  });
});