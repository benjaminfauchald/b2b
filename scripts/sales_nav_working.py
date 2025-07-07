#!/usr/bin/env python3
"""
Working Sales Navigator scraper for users with active subscription
"""

import os
import json
import asyncio
from typing import Dict, List
from scrapfly import ScrapeConfig, ScrapflyClient
from parsel import Selector

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

def build_full_cookies() -> Dict[str, str]:
    """Build complete LinkedIn cookie set"""
    cookies = {}
    
    # Essential cookies
    if os.environ.get("LINKEDIN_COOKIE_LI_AT"):
        cookies["li_at"] = os.environ.get("LINKEDIN_COOKIE_LI_AT")
    
    if os.environ.get("LINKEDIN_COOKIE_JSESSIONID"):
        cookies["JSESSIONID"] = os.environ.get("LINKEDIN_COOKIE_JSESSIONID").strip('"')
    
    if os.environ.get("LINKEDIN_COOKIE_BCOOKIE"):
        cookies["bcookie"] = os.environ.get("LINKEDIN_COOKIE_BCOOKIE").strip('"')
    
    if os.environ.get("LINKEDIN_COOKIE_BSCOOKIE"):
        cookies["bscookie"] = os.environ.get("LINKEDIN_COOKIE_BSCOOKIE").strip('"')
    
    # Additional cookies that might help with Sales Navigator
    cookies.update({
        "liap": "true",
        "li_theme": "light",
        "li_theme_set": "app",
        "timezone": "Europe/Oslo",
        "lang": "v=2&lang=en-us"
    })
    
    return cookies

async def scrape_sales_navigator_with_subscription(url: str) -> Dict:
    """Scrape Sales Navigator with proper subscription handling"""
    
    cookies = build_full_cookies()
    
    # More aggressive JavaScript execution for Sales Navigator
    js_script = """
    new Promise((resolve) => {
        console.log('Starting Sales Navigator wait script');
        
        let attempts = 0;
        const maxAttempts = 40; // 2 minutes max
        
        const checkForContent = () => {
            attempts++;
            console.log(`Attempt ${attempts}/${maxAttempts}`);
            
            // Remove loading screen first if it exists
            const loadingScreen = document.querySelector('.initial-loading-state');
            if (loadingScreen) {
                loadingScreen.style.display = 'none';
            }
            
            // Look for various result containers
            const resultSelectors = [
                '.reusable-search__result-container .result',
                '.search-results-container .result',
                '.reusable-search__entities-container li',
                '.search-results__list li',
                '[data-x-search-result]',
                '.artdeco-list li',
                '.search-result',
                '.result-lockup',
                '.member-result'
            ];
            
            let foundResults = false;
            for (const selector of resultSelectors) {
                const elements = document.querySelectorAll(selector);
                if (elements.length > 0) {
                    console.log(`Found ${elements.length} results with selector: ${selector}`);
                    foundResults = true;
                    break;
                }
            }
            
            if (foundResults) {
                resolve(true);
                return;
            }
            
            // Check for error states
            const errorSelectors = [
                '.empty-state',
                '.error-state', 
                '.no-results',
                '.search-no-results'
            ];
            
            for (const selector of errorSelectors) {
                if (document.querySelector(selector)) {
                    console.log(`Found error state: ${selector}`);
                    resolve(true);
                    return;
                }
            }
            
            // Check if we have any meaningful content
            const bodyText = document.body.innerText.toLowerCase();
            if (bodyText.includes('search results') || 
                bodyText.includes('people found') || 
                bodyText.includes('no results') ||
                bodyText.includes('try adjusting')) {
                console.log('Found search-related content in text');
                resolve(true);
                return;
            }
            
            // Continue checking if we haven't reached max attempts
            if (attempts < maxAttempts) {
                setTimeout(checkForContent, 3000);
            } else {
                console.log('Max attempts reached, resolving anyway');
                resolve(true);
            }
        };
        
        // Start checking after initial delay
        setTimeout(checkForContent, 5000);
    });
    """
    
    config = ScrapeConfig(
        url,
        cookies=cookies,
        asp=True,
        country="US",
        headers={
            "Accept-Language": "en-US,en;q=0.5",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Encoding": "gzip, deflate, br",
            "DNT": "1",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1"
        },
        render_js=True,
        js=js_script,
        proxy_pool="public_residential_pool",
        session="sales_nav_subscription"
    )
    
    try:
        print(f"🚀 Scraping Sales Navigator with subscription...")
        print(f"🔗 URL: {url}")
        print(f"🍪 Using {len(cookies)} cookies")
        
        response = await SCRAPFLY.async_scrape(config)
        
        print(f"📄 Response: {response.status_code}")
        print(f"📊 Size: {len(response.content)} bytes")
        
        # Save response for debugging
        os.makedirs("tmp/debug", exist_ok=True)
        with open("tmp/debug/sales_nav_subscription.html", "w", encoding="utf-8") as f:
            f.write(response.content)
        
        # Parse results with multiple strategies
        profiles = extract_sales_nav_profiles(response.selector)
        
        result = {
            "success": len(profiles) > 0,
            "profiles": profiles,
            "total_found": len(profiles),
            "url": url,
            "status_code": response.status_code,
            "content_size": len(response.content)
        }
        
        if len(profiles) > 0:
            print(f"🎉 SUCCESS! Found {len(profiles)} profiles")
            for i, profile in enumerate(profiles[:3]):
                print(f"  {i+1}. {profile.get('name', 'No name')} - {profile.get('title', 'No title')}")
        else:
            print(f"⚠️ No profiles found - analyzing page content...")
            analysis = analyze_sales_nav_page(response.selector)
            result["analysis"] = analysis
            print(f"   Title: {analysis.get('title', 'Unknown')}")
            print(f"   Has subscription prompt: {analysis.get('has_subscription_prompt', False)}")
            print(f"   Has search interface: {analysis.get('has_search_interface', False)}")
            print(f"   Content type: {analysis.get('content_type', 'Unknown')}")
        
        return result
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return {
            "success": False,
            "error": str(e),
            "url": url
        }

def extract_sales_nav_profiles(selector: Selector) -> List[Dict]:
    """Extract profiles from Sales Navigator with multiple strategies"""
    profiles = []
    
    # Strategy 1: Modern Sales Navigator selectors
    result_containers = [
        '.reusable-search__result-container .result',
        '.search-results-container .result', 
        '.reusable-search__entities-container li',
        '.search-results__list li',
        '[data-x-search-result]',
        '.artdeco-list li',
        '.search-result',
        '.result-lockup',
        '.member-result'
    ]
    
    for container_selector in result_containers:
        containers = selector.css(container_selector)
        print(f"  Trying {container_selector}: {len(containers)} containers")
        
        for idx, container in enumerate(containers):
            profile = extract_profile_from_sales_nav_container(container, idx)
            if profile:
                profiles.append(profile)
    
    # Strategy 2: Look for any profile links and extract context
    profile_links = selector.css('a[href*="/sales/people/"], a[href*="/in/"]')
    print(f"  Found {len(profile_links)} profile links")
    
    for idx, link in enumerate(profile_links):
        profile = extract_profile_from_link_context(link, idx)
        if profile:
            profiles.append(profile)
    
    # Strategy 3: JSON data extraction
    scripts = selector.css('script::text').getall()
    for script in scripts:
        if 'voyager' in script.lower() or 'search' in script.lower():
            try:
                # Try to extract any JSON that might contain profile data
                import re
                json_matches = re.findall(r'\{[^{}]*"firstName"[^{}]*\}', script)
                for match in json_matches:
                    try:
                        data = json.loads(match)
                        if 'firstName' in data:
                            profile = {
                                "name": f"{data.get('firstName', '')} {data.get('lastName', '')}".strip(),
                                "title": data.get('headline', ''),
                                "company": data.get('companyName', ''),
                                "location": data.get('location', ''),
                                "profile_url": data.get('profileUrl', ''),
                                "source": "json_extraction"
                            }
                            if profile["name"]:
                                profiles.append(profile)
                    except:
                        continue
            except:
                continue
    
    # Remove duplicates
    unique_profiles = []
    seen = set()
    for profile in profiles:
        key = profile.get('name', '') + profile.get('profile_url', '')
        if key and key not in seen:
            seen.add(key)
            unique_profiles.append(profile)
    
    return unique_profiles

def extract_profile_from_sales_nav_container(container, idx: int) -> Dict:
    """Extract profile from Sales Navigator result container"""
    try:
        # Multiple name extraction approaches
        name_selectors = [
            '.result-lockup__name a::text',
            '.result-lockup__name::text',
            '.member-result__info h3 a::text',
            '.member-result__info h3::text',
            'h3 a::text',
            'h3::text',
            '.name a::text',
            '.name::text',
            '[data-control-name*="profile"] span::text'
        ]
        
        name = ""
        for sel in name_selectors:
            result = container.css(sel).get()
            if result and result.strip():
                name = result.strip()
                break
        
        # Title extraction
        title_selectors = [
            '.result-lockup__highlight-keyword::text',
            '.member-result__info .subline::text',
            '.headline::text',
            '.result-lockup__position::text'
        ]
        
        title = ""
        for sel in title_selectors:
            result = container.css(sel).get()
            if result and result.strip():
                title = result.strip()
                break
        
        # Company extraction
        company_selectors = [
            '.result-lockup__position-company a::text',
            '.result-lockup__position-company::text',
            '.member-result__info .subline a::text',
            '.company-name::text'
        ]
        
        company = ""
        for sel in company_selectors:
            result = container.css(sel).get()
            if result and result.strip():
                company = result.strip()
                break
        
        # Profile URL
        profile_url = ""
        url_selectors = [
            'a[href*="/sales/people/"]::attr(href)',
            'a[href*="/in/"]::attr(href)',
            'h3 a::attr(href)'
        ]
        
        for sel in url_selectors:
            result = container.css(sel).get()
            if result:
                profile_url = result
                if not profile_url.startswith('http'):
                    profile_url = 'https://www.linkedin.com' + profile_url
                break
        
        if name:
            return {
                "name": name,
                "title": title,
                "company": company,
                "location": "",
                "profile_url": profile_url,
                "source": "sales_nav_container",
                "index": idx
            }
    
    except Exception as e:
        print(f"    Error extracting from container {idx}: {e}")
    
    return None

def extract_profile_from_link_context(link, idx: int) -> Dict:
    """Extract profile from link and surrounding context"""
    try:
        href = link.css('::attr(href)').get() or ""
        text = link.css('::text').get() or ""
        
        if not href.startswith('http'):
            href = 'https://www.linkedin.com' + href
        
        # Look for context in parent elements
        parent = link.xpath('../..')
        if parent:
            all_text = parent.css('::text').getall()
            all_text = [t.strip() for t in all_text if t.strip() and len(t.strip()) > 2]
            
            name = text.strip() if text.strip() else (all_text[0] if all_text else "")
            title = all_text[1] if len(all_text) > 1 else ""
            
            if name:
                return {
                    "name": name,
                    "title": title,
                    "company": "",
                    "location": "",
                    "profile_url": href,
                    "source": "link_context",
                    "index": idx
                }
    
    except Exception as e:
        print(f"    Error extracting from link {idx}: {e}")
    
    return None

def analyze_sales_nav_page(selector: Selector) -> Dict:
    """Analyze what type of Sales Navigator page we received"""
    
    title = selector.css("title::text").get() or ""
    content = selector.get().lower()
    
    return {
        "title": title,
        "has_loading_screen": "loading" in content or "initial-load" in content,
        "has_subscription_prompt": "upgrade" in content or "premium" in content,
        "has_search_interface": "search" in content and ("filters" in content or "results" in content),
        "has_login_prompt": "sign in" in content or "login" in content,
        "content_type": "loading" if "initial-load" in content else "search" if "search" in content else "unknown",
        "total_links": len(selector.css('a')),
        "profile_links": len(selector.css('a[href*="/in/"], a[href*="/sales/people/"]')),
        "content_size": len(content)
    }

async def test_sales_nav_with_subscription():
    """Test Sales Navigator with active subscription"""
    
    if not os.environ.get("SCRAPFLY_API_KEY"):
        print("❌ SCRAPFLY_API_KEY required")
        return
    
    # Test the provided URL
    test_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    print("🎯 Testing Sales Navigator with Active Subscription")
    print("=" * 60)
    
    result = await scrape_sales_navigator_with_subscription(test_url)
    
    # Save results
    with open("tmp/sales_nav_subscription_results.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved to tmp/sales_nav_subscription_results.json")
    
    return result

if __name__ == "__main__":
    asyncio.run(test_sales_nav_with_subscription())