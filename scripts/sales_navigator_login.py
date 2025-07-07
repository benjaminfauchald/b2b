#!/usr/bin/env python3
"""
Sales Navigator scraper with login capability
"""

import os
import json
import time
import asyncio
from typing import Dict, List, Optional
from scrapfly import ScrapeConfig, ScrapflyClient

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

async def linkedin_login_and_scrape(target_url: str) -> Dict:
    """Login to LinkedIn and then scrape Sales Navigator"""
    
    print("🔑 Step 1: Attempting LinkedIn login...")
    
    # First, try to login to LinkedIn
    login_config = ScrapeConfig(
        "https://www.linkedin.com/login",
        asp=True,
        country="US",
        render_js=True,
        js=f"""
        // Wait for login page to load
        await new Promise(resolve => setTimeout(resolve, 3000));
        
        // Fill in login credentials
        const emailField = document.querySelector('#username');
        const passwordField = document.querySelector('#password');
        const submitButton = document.querySelector('.login__form_action_container button');
        
        if (emailField && passwordField && submitButton) {{
            emailField.value = '{os.environ.get("LINKEDIN_EMAIL", "")}';
            passwordField.value = '{os.environ.get("LINKEDIN_PASSWORD", "")}';
            
            // Wait a bit then submit
            await new Promise(resolve => setTimeout(resolve, 1000));
            submitButton.click();
            
            // Wait for redirect after login
            await new Promise(resolve => setTimeout(resolve, 5000));
        }}
        """,
        session="linkedin_login_session"
    )
    
    try:
        login_response = await SCRAPFLY.async_scrape(login_config)
        print(f"✅ Login response: {login_response.status_code}")
        
        # Now try to access Sales Navigator with the same session
        print("🎯 Step 2: Accessing Sales Navigator...")
        
        sales_nav_config = ScrapeConfig(
            target_url,
            asp=True,
            country="US", 
            render_js=True,
            js="""
            // Wait for Sales Navigator to load
            new Promise((resolve) => {
                const checkForContent = () => {
                    // Check for search results
                    const results = document.querySelectorAll('[data-x-search-result], .search-results__result-item, .result-lockup');
                    if (results.length > 0) {
                        console.log('Found search results!');
                        resolve(true);
                        return;
                    }
                    
                    // Check for loading screen
                    const loading = document.querySelector('.initial-loading-state');
                    if (loading) {
                        console.log('Still loading...');
                        setTimeout(checkForContent, 3000);
                        return;
                    }
                    
                    // Check for any content
                    const bodyText = document.body.innerText.toLowerCase();
                    if (bodyText.includes('people') || bodyText.includes('results') || bodyText.includes('search')) {
                        console.log('Found some search-related content');
                        resolve(true);
                        return;
                    }
                    
                    setTimeout(checkForContent, 3000);
                };
                
                setTimeout(checkForContent, 2000);
                
                // Max timeout
                setTimeout(() => resolve(true), 20000);
            });
            """,
            session="linkedin_login_session"  # Use same session
        )
        
        sales_response = await SCRAPFLY.async_scrape(sales_nav_config)
        
        print(f"📄 Sales Navigator response: {sales_response.status_code}")
        print(f"📊 Content size: {len(sales_response.content)} bytes")
        
        # Save the response for analysis
        os.makedirs("tmp/debug", exist_ok=True)
        with open("tmp/debug/sales_nav_after_login.html", "w", encoding="utf-8") as f:
            f.write(sales_response.content)
        
        # Analyze the content
        selector = sales_response.selector
        title = selector.css("title::text").get() or ""
        
        # Look for different types of content
        search_results = selector.css('[data-x-search-result], .search-results__result-item, .result-lockup')
        loading_elements = selector.css('.initial-loading-state, .loading-bar')
        
        # Try to extract any profiles we can find
        profiles = []
        
        # Try basic profile extraction
        name_elements = selector.css('[data-anonymize="person-name"], .result-lockup__name, h3 a')
        for idx, element in enumerate(name_elements):
            name = element.css('::text').get()
            if name and name.strip():
                profiles.append({
                    "name": name.strip(),
                    "title": "",
                    "company": "",
                    "source": "name_element",
                    "index": idx
                })
        
        # Try extracting any LinkedIn profile links
        profile_links = selector.css('a[href*="/in/"], a[href*="/sales/people/"]')
        for idx, link in enumerate(profile_links):
            href = link.css('::attr(href)').get()
            text = link.css('::text').get()
            if href and text:
                profiles.append({
                    "name": text.strip(),
                    "profile_url": href,
                    "source": "profile_link",
                    "index": idx
                })
        
        result = {
            "success": len(profiles) > 0,
            "login_status": login_response.status_code,
            "sales_nav_status": sales_response.status_code,
            "title": title,
            "profiles": profiles,
            "total_found": len(profiles),
            "has_search_results": len(search_results) > 0,
            "has_loading": len(loading_elements) > 0,
            "content_size": len(sales_response.content),
            "url": target_url
        }
        
        return result
        
    except Exception as e:
        print(f"❌ Error during login/scrape: {e}")
        return {
            "success": False,
            "error": str(e),
            "url": target_url
        }

async def test_sales_navigator_with_login():
    """Test Sales Navigator access with login"""
    
    if not all([
        os.environ.get("SCRAPFLY_API_KEY"),
        os.environ.get("LINKEDIN_EMAIL"), 
        os.environ.get("LINKEDIN_PASSWORD")
    ]):
        print("❌ Missing required environment variables:")
        print("  - SCRAPFLY_API_KEY")
        print("  - LINKEDIN_EMAIL") 
        print("  - LINKEDIN_PASSWORD")
        return
    
    target_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    print("🚀 Testing Sales Navigator with login flow...")
    print(f"🎯 Target URL: {target_url}")
    
    result = await linkedin_login_and_scrape(target_url)
    
    # Save results
    with open("tmp/sales_nav_login_results.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved to tmp/sales_nav_login_results.json")
    
    # Print summary
    if result.get("success"):
        print(f"✅ SUCCESS! Found {result['total_found']} profiles")
        for i, profile in enumerate(result["profiles"][:5]):
            print(f"  {i+1}. {profile['name']} (via {profile['source']})")
    else:
        print(f"❌ FAILED: {result.get('error', 'No profiles found')}")
        print(f"📄 Title: {result.get('title', 'Unknown')}")
        print(f"🔄 Has loading: {result.get('has_loading', False)}")
        print(f"📊 Has search results: {result.get('has_search_results', False)}")
    
    return result

if __name__ == "__main__":
    asyncio.run(test_sales_navigator_with_login())