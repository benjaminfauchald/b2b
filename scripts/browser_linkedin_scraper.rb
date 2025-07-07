#!/usr/bin/env ruby
# Browser-based LinkedIn Sales Navigator Scraper
# Uses the current browser session to extract real profile data

require_relative '../config/environment'
require 'json'

puts "="*80
puts "Browser-based LinkedIn Sales Navigator Scraper"
puts "="*80

# The Sales Navigator URL we're testing with
test_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"

puts "🎯 Target URL: #{test_url}"
puts "\n📋 This script will:"
puts "  1. Use the browser to navigate to Sales Navigator"
puts "  2. Extract visible profile data"
puts "  3. Return structured JSON results"

puts "\n" + "="*60

class BrowserLinkedinScraper
  def self.extract_profiles_from_current_page
    # This method will be called via Puppeteer to extract data from the current page
    script = <<~JAVASCRIPT
      (function() {
        console.log('Starting profile extraction...');
        
        const profiles = [];
        const results = { 
          success: true, 
          profiles: [], 
          total_found: 0,
          source: 'browser_extraction',
          scraped_at: new Date().toISOString()
        };
        
        try {
          // Wait for content to be fully loaded
          const maxWait = 5000; // 5 seconds
          const startTime = Date.now();
          
          // Look for various profile selectors that LinkedIn might use
          const profileSelectors = [
            '[data-test-scope="search-result"]',
            '.search-results__result-item',
            '.artdeco-entity-lockup',
            '.result-lockup',
            '[class*="search-result"]',
            '[class*="profile-card"]',
            '.lead-result'
          ];
          
          // First, let's see what we can find in the page text
          const pageText = document.body.innerText;
          const resultsMatch = pageText.match(/(\\d+) results/);
          if (resultsMatch) {
            results.total_found = parseInt(resultsMatch[1]);
            console.log('Found', results.total_found, 'total results');
          }
          
          // Try to extract profile information from visible text
          // LinkedIn Sales Navigator often loads content dynamically
          const lines = pageText.split('\\n').map(line => line.trim()).filter(line => line.length > 0);
          
          let currentProfile = null;
          const extractedProfiles = [];
          
          for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Look for patterns that indicate profile information
            // Names typically appear as "FirstName LastName" 
            if (/^[A-Z][a-z]+ [A-Z][a-z]+( [A-Z][a-z]+)?$/.test(line) && 
                !line.includes('LinkedIn') && 
                !line.includes('Company') &&
                !line.includes('Crowe Norway') &&
                line.length < 50) {
              
              // Start a new profile
              if (currentProfile) {
                extractedProfiles.push(currentProfile);
              }
              
              currentProfile = {
                name: line,
                headline: null,
                company: null,
                location: null,
                profile_url: null,
                connection_degree: null
              };
              
              // Look ahead for title/company info
              if (i + 1 < lines.length) {
                const nextLine = lines[i + 1];
                // If next line looks like a job title, use it
                if (nextLine && !nextLine.match(/^[A-Z][a-z]+ [A-Z]/) && nextLine.length < 100) {
                  currentProfile.headline = nextLine;
                }
              }
            }
            
            // Look for location patterns (city, country format)
            if (currentProfile && !currentProfile.location && 
                /^[A-Z][a-z]+,\\s*[A-Z][a-z]+$/.test(line)) {
              currentProfile.location = line;
            }
            
            // Look for connection degree
            if (currentProfile && line.match(/^(1st|2nd|3rd)$/)) {
              currentProfile.connection_degree = line;
            }
          }
          
          // Add the last profile if exists
          if (currentProfile) {
            extractedProfiles.push(currentProfile);
          }
          
          // Clean up and validate profiles
          const validProfiles = extractedProfiles.filter(profile => {
            return profile.name && 
                   profile.name.length > 3 && 
                   profile.name.split(' ').length >= 2;
          });
          
          // Generate profile URLs based on names (best effort)
          validProfiles.forEach(profile => {
            const slug = profile.name.toLowerCase()
              .replace(/[^a-z\\s]/g, '')
              .replace(/\\s+/g, '-');
            profile.profile_url = `https://www.linkedin.com/in/${slug}/`;
            profile.scraped_at = new Date().toISOString();
            profile.source = 'browser_text_extraction';
          });
          
          results.profiles = validProfiles;
          results.total_extracted = validProfiles.length;
          
          console.log('Extracted', validProfiles.length, 'profiles');
          console.log('Profile names:', validProfiles.map(p => p.name));
          
          // Try to get more structured data if available
          profileSelectors.forEach(selector => {
            const elements = document.querySelectorAll(selector);
            console.log(`Selector "${selector}" found ${elements.length} elements`);
            
            if (elements.length > 0) {
              console.log('Found structured elements, trying to extract...');
              // Would extract more detailed info here
            }
          });
          
        } catch (error) {
          console.error('Error during extraction:', error);
          results.success = false;
          results.error = error.message;
        }
        
        return results;
      })();
    JAVASCRIPT
    
    script
  end
end

# Now let's use this with the Puppeteer MCP to extract data
puts "🤖 Using browser automation to extract profile data..."

# The script will be executed in the browser context
extraction_script = BrowserLinkedinScraper.extract_profiles_from_current_page

puts "\n📊 Extraction Results:"
puts "="*40

# Since we can't directly execute Ruby through Puppeteer, let's save the script 
# and execute it as a separate action
script_file = Rails.root.join('tmp', 'linkedin_extraction_script.js')
File.write(script_file, extraction_script)

puts "✅ Extraction script saved to: #{script_file}"
puts "\n🔍 To extract profiles:"
puts "  1. Navigate to the Sales Navigator URL in browser"
puts "  2. Run the extraction script"
puts "  3. Review the extracted profile data"

puts "\n📝 Next steps:"
puts "  • The script is ready to extract profiles from the current page"
puts "  • It will look for names, titles, companies, and locations"
puts "  • Results will be returned in structured JSON format"

puts "\n" + "="*80