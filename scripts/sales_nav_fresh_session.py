#!/usr/bin/env python3
"""
Sales Navigator with fresh session approach
"""

import os
import json
import asyncio
from scrapfly import ScrapeConfig, ScrapflyClient

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

async def establish_fresh_sales_nav_session():
    """Establish a fresh Sales Navigator session before scraping"""
    
    cookies = {"li_at": os.environ.get("LINKEDIN_COOKIE_LI_AT", "")}
    
    print("🔄 Step 1: Establishing fresh Sales Navigator session...")
    
    # First, access Sales Navigator home to establish session
    home_config = ScrapeConfig(
        "https://www.linkedin.com/sales/",
        cookies=cookies,
        asp=True,
        country="US",
        render_js=True,
        js="""
        new Promise(resolve => {
            console.log('Accessing Sales Navigator home...');
            setTimeout(() => {
                console.log('Sales Navigator home loaded');
                resolve(true);
            }, 8000);
        });
        """,
        session="fresh_sales_nav"
    )
    
    try:
        home_response = await SCRAPFLY.async_scrape(home_config)
        print(f"✅ Sales Navigator home: {home_response.status_code}")
        
        # Check what we got
        title = home_response.selector.css("title::text").get() or ""
        content = home_response.content.lower()
        
        has_subscription_access = "sales navigator" in content and "upgrade" not in content
        has_search_access = "search" in content or "people" in content
        
        print(f"📄 Title: {title}")
        print(f"💼 Has subscription access: {has_subscription_access}")
        print(f"🔍 Has search access: {has_search_access}")
        
        if not has_subscription_access:
            print("⚠️ No subscription access detected - checking if we need to navigate to search...")
            
            # Try to navigate to people search
            search_config = ScrapeConfig(
                "https://www.linkedin.com/sales/search/people",
                cookies=cookies,
                asp=True,
                country="US",
                render_js=True,
                js="""
                new Promise(resolve => {
                    console.log('Accessing people search...');
                    setTimeout(() => {
                        console.log('People search loaded');
                        resolve(true);
                    }, 10000);
                });
                """,
                session="fresh_sales_nav"  # Same session
            )
            
            search_response = await SCRAPFLY.async_scrape(search_config)
            print(f"✅ People search: {search_response.status_code}")
            
            search_title = search_response.selector.css("title::text").get() or ""
            search_content = search_response.content.lower()
            
            print(f"📄 Search title: {search_title}")
            print(f"🔍 Has search interface: {'search' in search_content}")
            
            # Save this response for analysis
            with open("tmp/debug/sales_nav_search_page.html", "w", encoding="utf-8") as f:
                f.write(search_response.content)
            
            return search_response, "fresh_sales_nav"
        
        return home_response, "fresh_sales_nav"
        
    except Exception as e:
        print(f"❌ Error establishing session: {e}")
        return None, None

async def scrape_with_fresh_session(target_url: str):
    """Scrape target URL with fresh session"""
    
    # First establish session
    session_response, session_id = await establish_fresh_sales_nav_session()
    
    if not session_response:
        return {"success": False, "error": "Could not establish session"}
    
    print(f"\n🎯 Step 2: Scraping target URL with fresh session...")
    
    # Now scrape the target URL
    target_config = ScrapeConfig(
        target_url,
        asp=True,
        country="US",
        render_js=True,
        js="""
        new Promise(resolve => {
            console.log('Loading target Sales Navigator URL...');
            
            let attempts = 0;
            const maxAttempts = 30;
            
            const checkContent = () => {
                attempts++;
                console.log(`Checking content, attempt ${attempts}`);
                
                // Look for actual search results
                const resultSelectors = [
                    '.reusable-search__result-container',
                    '.search-results-container', 
                    '.search-results__list',
                    '.artdeco-list',
                    '[data-x-search-result]'
                ];
                
                for (const selector of resultSelectors) {
                    const elements = document.querySelectorAll(selector + ' li, ' + selector + ' .result');
                    if (elements.length > 0) {
                        console.log(`Found ${elements.length} results with ${selector}`);
                        resolve(true);
                        return;
                    }
                }
                
                // Check for "no results" message
                const noResultsSelectors = [
                    '.empty-state',
                    '.no-results',
                    '.search-no-results'
                ];
                
                for (const selector of noResultsSelectors) {
                    if (document.querySelector(selector)) {
                        console.log(`Found no results state: ${selector}`);
                        resolve(true);
                        return;
                    }
                }
                
                // Check body text for search indicators
                const bodyText = document.body.innerText.toLowerCase();
                if (bodyText.includes('results for') || 
                    bodyText.includes('people found') ||
                    bodyText.includes('no people found') ||
                    bodyText.includes('try adjusting your search')) {
                    console.log('Found search results text');
                    resolve(true);
                    return;
                }
                
                if (attempts < maxAttempts) {
                    setTimeout(checkContent, 3000);
                } else {
                    console.log('Max attempts reached');
                    resolve(true);
                }
            };
            
            setTimeout(checkContent, 5000);
        });
        """,
        session=session_id  # Use the established session
    )
    
    try:
        response = await SCRAPFLY.async_scrape(target_config)
        
        print(f"📄 Target response: {response.status_code}")
        print(f"📊 Content size: {len(response.content)} bytes")
        
        # Save for analysis
        with open("tmp/debug/target_with_fresh_session.html", "w", encoding="utf-8") as f:
            f.write(response.content)
        
        # Analyze content
        selector = response.selector
        title = selector.css("title::text").get() or ""
        content = response.content.lower()
        
        # Look for different content types
        has_loading = "loading" in content or "initial-load" in content
        has_results = len(selector.css('.reusable-search__result-container li, .search-results li, [data-x-search-result]')) > 0
        has_no_results = "no people found" in content or "no results" in content
        has_search_interface = "search" in content and "filters" in content
        
        print(f"📄 Title: {title}")
        print(f"⏳ Has loading: {has_loading}")
        print(f"📋 Has results: {has_results}")
        print(f"🚫 Has no results: {has_no_results}")
        print(f"🔍 Has search interface: {has_search_interface}")
        
        # Try to extract any profiles we can find
        profiles = []
        
        # Look for profile links with context
        profile_links = selector.css('a[href*="/sales/people/"], a[href*="/in/"]')
        print(f"🔗 Found {len(profile_links)} profile links")
        
        for idx, link in enumerate(profile_links):
            href = link.css('::attr(href)').get() or ""
            text = link.css('::text').get() or ""
            
            if text.strip() and len(text.strip()) > 2:
                profiles.append({
                    "name": text.strip(),
                    "profile_url": href if href.startswith('http') else f"https://www.linkedin.com{href}",
                    "source": "profile_link",
                    "index": idx
                })
        
        # Look for any name-like text patterns
        name_elements = selector.css('h3, h4, .name, [class*="name"]')
        for idx, element in enumerate(name_elements):
            text = element.css('::text').get()
            if text and text.strip() and len(text.strip().split()) >= 2:
                # Looks like a name
                profiles.append({
                    "name": text.strip(),
                    "source": "name_element",
                    "index": idx
                })
        
        # Remove duplicates
        unique_profiles = []
        seen_names = set()
        for profile in profiles:
            name = profile.get('name', '').lower()
            if name and name not in seen_names:
                seen_names.add(name)
                unique_profiles.append(profile)
        
        result = {
            "success": len(unique_profiles) > 0 or has_no_results,
            "profiles": unique_profiles,
            "total_found": len(unique_profiles),
            "has_loading": has_loading,
            "has_results": has_results,
            "has_no_results": has_no_results,
            "has_search_interface": has_search_interface,
            "title": title,
            "url": target_url,
            "status_code": response.status_code
        }
        
        return result
        
    except Exception as e:
        print(f"❌ Error scraping target: {e}")
        return {"success": False, "error": str(e)}

async def test_fresh_session_approach():
    """Test the fresh session approach"""
    
    if not os.environ.get("SCRAPFLY_API_KEY"):
        print("❌ SCRAPFLY_API_KEY required")
        return
    
    target_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    print("🔄 Testing Sales Navigator with Fresh Session Approach")
    print("=" * 65)
    
    result = await scrape_with_fresh_session(target_url)
    
    # Save results
    os.makedirs("tmp", exist_ok=True)
    with open("tmp/fresh_session_results.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved to tmp/fresh_session_results.json")
    
    if result.get("success"):
        print(f"🎉 SUCCESS!")
        if result.get("has_no_results"):
            print(f"📋 No people found for this company (this is a valid result)")
        else:
            print(f"📋 Found {result['total_found']} profiles:")
            for i, profile in enumerate(result["profiles"][:5]):
                print(f"  {i+1}. {profile['name']} (via {profile['source']})")
    else:
        print(f"❌ FAILED: {result.get('error', 'Unknown error')}")
    
    return result

if __name__ == "__main__":
    asyncio.run(test_fresh_session_approach())