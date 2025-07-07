#!/usr/bin/env python3
"""
Advanced Sales Navigator Scraper with proper dynamic content handling

This version uses ScrapFly with advanced JavaScript rendering to wait for
the actual search results to load, not just the initial loading screen.
"""

import os
import json
import time
import asyncio
from typing import Dict, List, Optional
from urllib.parse import urlencode, quote_plus, unquote
from parsel import Selector
from loguru import logger as log
from scrapfly import ScrapeConfig, ScrapflyClient, ScrapeApiResponse

# Initialize ScrapFly client
SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

# Advanced configuration for Sales Navigator
BASE_CONFIG = {
    "asp": True,
    "country": "US",
    "headers": {
        "Accept-Language": "en-US,en;q=0.5",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Encoding": "gzip, deflate, br",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache"
    },
    "render_js": True,
    # Wait for specific content to appear - this is key for Sales Navigator
    "js": """
    // Wait for Sales Navigator search results to load
    new Promise((resolve) => {
        const checkForResults = () => {
            // Check for various possible result containers
            const resultSelectors = [
                '[data-x-search-result]',
                '.search-results__result-item',
                '.reusable-search__result-container',
                '.search-results-container',
                '.artdeco-list__item',
                '[data-test-id*="result"]',
                '.result-lockup'
            ];
            
            for (let selector of resultSelectors) {
                const elements = document.querySelectorAll(selector);
                if (elements.length > 0) {
                    console.log(`Found ${elements.length} results with selector: ${selector}`);
                    resolve(true);
                    return;
                }
            }
            
            // Check if we're still on loading screen
            const loadingElements = document.querySelectorAll('.initial-loading-state, .loading-bar, .salesnav-image');
            if (loadingElements.length > 0) {
                console.log('Still on loading screen, waiting...');
                setTimeout(checkForResults, 2000);
                return;
            }
            
            // Check for error states
            const errorElements = document.querySelectorAll('.error-state, .empty-state, .no-results');
            if (errorElements.length > 0) {
                console.log('Found error or empty state');
                resolve(true);
                return;
            }
            
            // Check if page has loaded but no results (could be valid empty results)
            const bodyText = document.body.innerText.toLowerCase();
            if (bodyText.includes('search results') || bodyText.includes('people') || bodyText.includes('no results')) {
                console.log('Page loaded with search context');
                resolve(true);
                return;
            }
            
            // Continue waiting if none of the above conditions are met
            setTimeout(checkForResults, 2000);
        };
        
        // Start checking after initial delay
        setTimeout(checkForResults, 3000);
        
        // Max timeout of 30 seconds
        setTimeout(() => {
            console.log('Timeout reached, resolving anyway');
            resolve(true);
        }, 30000);
    });
    """,
    "proxy_pool": "public_residential_pool",
    "cache": False,
    "session": "linkedin_advanced_session"
}

def build_linkedin_cookies() -> Dict[str, str]:
    """Build LinkedIn cookies from environment variables"""
    cookies = {}
    
    if os.environ.get("LINKEDIN_COOKIE_LI_AT"):
        cookies["li_at"] = os.environ.get("LINKEDIN_COOKIE_LI_AT")
    
    if os.environ.get("LINKEDIN_COOKIE_JSESSIONID"):
        cookies["JSESSIONID"] = os.environ.get("LINKEDIN_COOKIE_JSESSIONID").strip('"')
    
    if os.environ.get("LINKEDIN_COOKIE_BCOOKIE"):
        cookies["bcookie"] = os.environ.get("LINKEDIN_COOKIE_BCOOKIE").strip('"')
    
    if os.environ.get("LINKEDIN_COOKIE_BSCOOKIE"):
        cookies["bscookie"] = os.environ.get("LINKEDIN_COOKIE_BSCOOKIE").strip('"')
    
    return cookies

def extract_profiles_comprehensive(selector: Selector) -> List[Dict]:
    """Comprehensive profile extraction using multiple strategies"""
    profiles = []
    
    # Strategy 1: Try modern Sales Navigator selectors
    log.info("Trying modern Sales Navigator selectors...")
    
    # Multiple container selectors to try
    container_selectors = [
        '[data-x-search-result]',
        '.search-results__result-item',
        '.reusable-search__result-container li',
        '.search-results-container li',
        '.artdeco-list__item',
        '[data-test-id*="result"]',
        '.result-lockup'
    ]
    
    for container_selector in container_selectors:
        containers = selector.css(container_selector)
        log.info(f"Found {len(containers)} containers with selector: {container_selector}")
        
        if len(containers) > 0:
            for idx, container in enumerate(containers):
                profile = extract_profile_from_container(container, idx, container_selector)
                if profile:
                    profiles.append(profile)
    
    # Strategy 2: Try generic person/profile selectors
    if not profiles:
        log.info("Trying generic person/profile selectors...")
        person_selectors = [
            '[data-anonymize="person-name"]',
            '.result-lockup__name',
            '[data-control-name*="profile"]',
            'a[href*="/in/"]'
        ]
        
        for selector_name in person_selectors:
            elements = selector.css(selector_name)
            log.info(f"Found {len(elements)} elements with selector: {selector_name}")
            
            for idx, element in enumerate(elements):
                profile = extract_profile_from_element(element, idx, selector_name)
                if profile:
                    profiles.append(profile)
    
    # Strategy 3: Try to find any LinkedIn profile links and extract around them
    if not profiles:
        log.info("Trying LinkedIn profile link detection...")
        profile_links = selector.css('a[href*="/in/"], a[href*="/sales/people/"], a[href*="linkedin.com"]')
        log.info(f"Found {len(profile_links)} LinkedIn links")
        
        for idx, link in enumerate(profile_links):
            profile = extract_profile_around_link(link, idx)
            if profile:
                profiles.append(profile)
    
    # Remove duplicates based on name or profile URL
    unique_profiles = []
    seen_identifiers = set()
    
    for profile in profiles:
        identifier = profile.get('name', '') + profile.get('profile_url', '')
        if identifier and identifier not in seen_identifiers:
            seen_identifiers.add(identifier)
            unique_profiles.append(profile)
    
    return unique_profiles

def extract_profile_from_container(container, idx: int, selector_used: str) -> Optional[Dict]:
    """Extract profile data from a container element"""
    try:
        # Try multiple name extraction strategies
        name = ""
        name_selectors = [
            '[data-anonymize="person-name"] span::text',
            '.result-lockup__name::text',
            '.result-lockup__name a::text',
            'h3 a::text',
            'h3::text',
            '.name::text',
            'a[data-control-name*="profile"]::text',
            'span[aria-hidden="true"]::text'
        ]
        
        for name_sel in name_selectors:
            name_result = container.css(name_sel).get()
            if name_result and name_result.strip():
                name = name_result.strip()
                break
        
        # Try multiple title extraction strategies
        title = ""
        title_selectors = [
            '[data-anonymize="person-title"]::text',
            '.result-lockup__highlight-keyword::text',
            '.result-lockup__position::text',
            '.member-insights__reason::text',
            '.subline::text',
            '.headline::text'
        ]
        
        for title_sel in title_selectors:
            title_result = container.css(title_sel).get()
            if title_result and title_result.strip():
                title = title_result.strip()
                break
        
        # Try company extraction
        company = ""
        company_selectors = [
            '[data-anonymize="company-name"]::text',
            '.result-lockup__position-company a::text',
            '.result-lockup__position-company::text',
            'a[data-control-name*="company"]::text'
        ]
        
        for company_sel in company_selectors:
            company_result = container.css(company_sel).get()
            if company_result and company_result.strip():
                company = company_result.strip()
                break
        
        # Try location extraction
        location = ""
        location_selectors = [
            '[data-anonymize="person-location"]::text',
            '.result-lockup__misc-item::text',
            '.member-insights__location::text',
            '.location::text'
        ]
        
        for location_sel in location_selectors:
            location_result = container.css(location_sel).get()
            if location_result and location_result.strip():
                location = location_result.strip()
                break
        
        # Try profile URL extraction
        profile_url = ""
        url_selectors = [
            'a[href*="/in/"]::attr(href)',
            'a[href*="/sales/people/"]::attr(href)',
            'a[data-control-name*="profile"]::attr(href)'
        ]
        
        for url_sel in url_selectors:
            url_result = container.css(url_sel).get()
            if url_result:
                profile_url = url_result
                if not profile_url.startswith('http'):
                    profile_url = 'https://www.linkedin.com' + profile_url
                break
        
        # Only return if we have at least a name
        if name:
            return {
                "name": name,
                "title": title,
                "company": company,
                "location": location,
                "profile_url": profile_url,
                "extraction_method": f"container_{selector_used}",
                "result_index": idx
            }
    
    except Exception as e:
        log.debug(f"Failed to extract from container {idx}: {e}")
    
    return None

def extract_profile_from_element(element, idx: int, selector_used: str) -> Optional[Dict]:
    """Extract profile data from a single element"""
    try:
        # For single elements, try to find related data in parent/sibling elements
        name = element.css('::text').get() or ""
        name = name.strip()
        
        # Look for title in nearby elements
        title = ""
        parent = element.xpath('..')
        if parent:
            title_candidates = parent.css('::text').getall()
            for candidate in title_candidates:
                candidate = candidate.strip()
                if candidate and candidate != name and len(candidate) > 5:
                    title = candidate
                    break
        
        profile_url = element.css('::attr(href)').get() or ""
        if profile_url and not profile_url.startswith('http'):
            profile_url = 'https://www.linkedin.com' + profile_url
        
        if name:
            return {
                "name": name,
                "title": title,
                "company": "",
                "location": "",
                "profile_url": profile_url,
                "extraction_method": f"element_{selector_used}",
                "result_index": idx
            }
    
    except Exception as e:
        log.debug(f"Failed to extract from element {idx}: {e}")
    
    return None

def extract_profile_around_link(link_element, idx: int) -> Optional[Dict]:
    """Extract profile data around a LinkedIn profile link"""
    try:
        profile_url = link_element.css('::attr(href)').get() or ""
        if not profile_url.startswith('http'):
            profile_url = 'https://www.linkedin.com' + profile_url
        
        name = link_element.css('::text').get() or ""
        name = name.strip()
        
        # Look in parent elements for more context
        parent = link_element.xpath('../..')
        if parent:
            all_text = parent.css('::text').getall()
            all_text = [t.strip() for t in all_text if t.strip()]
            
            # Simple heuristic: first non-empty text is likely the name
            if not name and all_text:
                name = all_text[0]
        
        if name:
            return {
                "name": name,
                "title": "",
                "company": "",
                "location": "",
                "profile_url": profile_url,
                "extraction_method": "link_detection",
                "result_index": idx
            }
    
    except Exception as e:
        log.debug(f"Failed to extract around link {idx}: {e}")
    
    return None

async def scrape_sales_navigator_advanced(url: str) -> Dict:
    """Advanced Sales Navigator scraping with proper wait conditions"""
    try:
        cookies = build_linkedin_cookies()
        
        config = ScrapeConfig(
            url,
            cookies=cookies,
            **BASE_CONFIG
        )
        
        log.info(f"🚀 Starting advanced scrape of: {url}")
        log.info(f"🔐 Using cookies: {list(cookies.keys())}")
        
        # Perform the scrape with advanced JavaScript handling
        response = await SCRAPFLY.async_scrape(config)
        
        log.info(f"📄 Response status: {response.status_code}")
        log.info(f"📊 Response size: {len(response.content)} bytes")
        
        # Save the final HTML for debugging
        os.makedirs("tmp/debug", exist_ok=True)
        with open("tmp/debug/final_page.html", "w", encoding="utf-8") as f:
            f.write(response.content)
        
        # Parse the response
        selector = response.selector
        
        # Extract profiles using comprehensive strategy
        profiles = extract_profiles_comprehensive(selector)
        
        # Additional debugging: save page analysis
        page_analysis = analyze_final_page(selector)
        with open("tmp/debug/final_analysis.json", "w", encoding="utf-8") as f:
            json.dump(page_analysis, f, indent=2, ensure_ascii=False)
        
        result = {
            "success": len(profiles) > 0,
            "results": profiles,
            "total_found": len(profiles),
            "url": url,
            "scraped_at": time.time(),
            "response_status": response.status_code,
            "response_size": len(response.content),
            "page_analysis": page_analysis
        }
        
        if len(profiles) > 0:
            log.success(f"🎉 Successfully extracted {len(profiles)} profiles!")
            for i, profile in enumerate(profiles[:3]):
                log.info(f"👤 Profile {i+1}: {profile['name']} - {profile['title']}")
        else:
            log.warning("⚠️ No profiles extracted - check debug files for analysis")
        
        return result
        
    except Exception as e:
        log.error(f"❌ Failed to scrape Sales Navigator: {e}")
        return {
            "success": False,
            "results": [],
            "total_found": 0,
            "error": str(e),
            "url": url
        }

def analyze_final_page(selector: Selector) -> Dict:
    """Analyze the final page to understand what we received"""
    
    title = selector.css("title::text").get() or ""
    
    # Check for various content types
    has_loading = len(selector.css('.initial-loading-state, .loading-bar, .salesnav-image')) > 0
    has_search_results = len(selector.css('[data-x-search-result], .search-results, .reusable-search')) > 0
    has_error = len(selector.css('.error-state, .empty-state')) > 0
    
    # Count different element types
    total_links = len(selector.css('a'))
    linkedin_links = len(selector.css('a[href*="/in/"], a[href*="/sales/people/"]'))
    result_containers = len(selector.css('[data-x-search-result], .search-results__result-item, .result-lockup'))
    
    # Get all class names
    all_classes = []
    for element in selector.css("*[class]"):
        classes = element.css("::attr(class)").get()
        if classes:
            all_classes.extend(classes.split())
    
    interesting_classes = [c for c in set(all_classes) if any(keyword in c.lower() for keyword in ['result', 'search', 'person', 'profile', 'member', 'lockup'])]
    
    # Check page text content
    body_text = selector.css('body').get() or ""
    has_sales_nav_content = any(term in body_text.lower() for term in ['sales navigator', 'search results', 'people search'])
    
    return {
        "title": title,
        "has_loading_screen": has_loading,
        "has_search_results": has_search_results,
        "has_error_state": has_error,
        "total_links": total_links,
        "linkedin_links": linkedin_links,
        "result_containers": result_containers,
        "interesting_classes": sorted(interesting_classes),
        "has_sales_nav_content": has_sales_nav_content,
        "page_size": len(body_text),
        "element_count": len(selector.css("*"))
    }

async def test_advanced_scraper():
    """Test the advanced Sales Navigator scraper"""
    
    if not os.environ.get("SCRAPFLY_API_KEY"):
        log.error("❌ SCRAPFLY_API_KEY environment variable is required")
        return
    
    test_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    log.info("🎯 Testing Advanced Sales Navigator Scraper")
    log.info(f"🔗 Target URL: {test_url}")
    
    result = await scrape_sales_navigator_advanced(test_url)
    
    # Save results
    output_file = "tmp/advanced_scraper_results.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    log.info(f"💾 Results saved to: {output_file}")
    
    # Print summary
    if result["success"]:
        log.success(f"✅ SUCCESS! Found {result['total_found']} profiles")
        print("\n📋 EXTRACTED PROFILES:")
        for i, profile in enumerate(result["results"]):
            print(f"  {i+1}. {profile['name']}")
            if profile['title']:
                print(f"     Title: {profile['title']}")
            if profile['company']:
                print(f"     Company: {profile['company']}")
            if profile['location']:
                print(f"     Location: {profile['location']}")
            print(f"     Method: {profile['extraction_method']}")
            print()
    else:
        log.error(f"❌ FAILED: {result.get('error', 'Unknown error')}")
        analysis = result.get('page_analysis', {})
        print(f"\n🔍 PAGE ANALYSIS:")
        print(f"  Title: {analysis.get('title', 'Unknown')}")
        print(f"  Has loading screen: {analysis.get('has_loading_screen', False)}")
        print(f"  Has search results: {analysis.get('has_search_results', False)}")
        print(f"  LinkedIn links found: {analysis.get('linkedin_links', 0)}")
        print(f"  Result containers: {analysis.get('result_containers', 0)}")
    
    return result

if __name__ == "__main__":
    asyncio.run(test_advanced_scraper())