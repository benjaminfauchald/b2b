#!/usr/bin/env python3
"""
Debug version of Sales Navigator Scraper to analyze page structure
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

# Base configuration for LinkedIn scraping with ScrapFly
BASE_CONFIG = {
    "asp": True,
    "country": "US", 
    "headers": {
        "Accept-Language": "en-US,en;q=0.5",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    },
    "render_js": True,
    "proxy_pool": "public_residential_pool",
    "cache": False,
    "session": "linkedin_debug_session"
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

async def debug_sales_navigator_page(url: str):
    """Debug the Sales Navigator page by saving HTML and analyzing structure"""
    try:
        cookies = build_linkedin_cookies()
        
        config = ScrapeConfig(
            url,
            cookies=cookies,
            **BASE_CONFIG
        )
        
        log.info(f"Debugging Sales Navigator URL: {url}")
        log.info(f"Using cookies: {list(cookies.keys())}")
        
        response = await SCRAPFLY.async_scrape(config)
        selector = response.selector
        
        # Save the full HTML for analysis
        os.makedirs("tmp/debug", exist_ok=True)
        
        with open("tmp/debug/sales_navigator_page.html", "w", encoding="utf-8") as f:
            f.write(response.content)
        
        log.info(f"✅ HTML saved to tmp/debug/sales_navigator_page.html")
        log.info(f"📊 Response status: {response.status_code}")
        log.info(f"📄 Response size: {len(response.content)} bytes")
        
        # Analyze page structure
        analysis = analyze_page_structure(selector)
        
        with open("tmp/debug/page_analysis.json", "w", encoding="utf-8") as f:
            json.dump(analysis, f, indent=2, ensure_ascii=False)
        
        log.info(f"📋 Page analysis saved to tmp/debug/page_analysis.json")
        
        # Print key findings
        print("\n🔍 KEY FINDINGS:")
        print(f"   Title: {analysis['title']}")
        print(f"   Is LinkedIn page: {analysis['is_linkedin']}")
        print(f"   Has sales navigator elements: {analysis['has_sales_nav_elements']}")
        print(f"   Has search results: {analysis['has_search_results']}")
        print(f"   Total elements with 'result': {analysis['result_element_count']}")
        print(f"   Total elements with 'person': {analysis['person_element_count']}")
        print(f"   Total elements with 'profile': {analysis['profile_element_count']}")
        
        print("\n📝 FOUND CLASSES:")
        for class_name in analysis['interesting_classes'][:10]:
            print(f"   {class_name}")
        
        return analysis
        
    except Exception as e:
        log.error(f"Failed to debug Sales Navigator page: {e}")
        return None

def analyze_page_structure(selector: Selector) -> Dict:
    """Analyze the page structure to understand Sales Navigator layout"""
    
    # Basic page info
    title = selector.css("title::text").get() or ""
    
    # Check if it's a LinkedIn page
    is_linkedin = "linkedin" in title.lower() or "linkedin" in selector.get()
    
    # Look for Sales Navigator specific elements
    sales_nav_keywords = ["sales", "navigator", "search", "people", "lead"]
    has_sales_nav_elements = any(keyword in selector.get().lower() for keyword in sales_nav_keywords)
    
    # Count different types of elements
    result_elements = selector.css("*").xpath(".//*[contains(@class, 'result') or contains(@data-test-id, 'result') or contains(@id, 'result')]")
    person_elements = selector.css("*").xpath(".//*[contains(@class, 'person') or contains(@data-test-id, 'person') or contains(@id, 'person')]")
    profile_elements = selector.css("*").xpath(".//*[contains(@class, 'profile') or contains(@data-test-id, 'profile') or contains(@id, 'profile')]")
    
    # Get all class names for analysis
    all_classes = []
    for element in selector.css("*[class]"):
        classes = element.css("::attr(class)").get()
        if classes:
            all_classes.extend(classes.split())
    
    # Find interesting classes (containing keywords)
    interesting_keywords = ["result", "search", "person", "profile", "card", "item", "list", "lead"]
    interesting_classes = []
    for class_name in set(all_classes):
        if any(keyword in class_name.lower() for keyword in interesting_keywords):
            interesting_classes.append(class_name)
    
    # Check for specific Sales Navigator selectors
    specific_selectors = {
        "data_x_search_result": len(selector.css("li[data-x-search-result]")),
        "search_results_class": len(selector.css(".search-results__result-item")),
        "person_name_anonymize": len(selector.css("[data-anonymize='person-name']")),
        "result_lockup": len(selector.css(".result-lockup")),
        "artdeco_list": len(selector.css(".artdeco-list")),
        "reusable_search": len(selector.css(".reusable-search")),
        "search_results_container": len(selector.css(".search-results-container")),
    }
    
    # Check for login/access issues
    access_issues = {
        "has_login_form": len(selector.css("form[data-test-id='login-form']")) > 0,
        "has_premium_upsell": "premium" in selector.get().lower() and "upgrade" in selector.get().lower(),
        "has_access_denied": "access denied" in selector.get().lower() or "unauthorized" in selector.get().lower(),
        "has_sales_nav_subscription": "sales navigator" in selector.get().lower() and "subscription" in selector.get().lower(),
    }
    
    return {
        "title": title,
        "is_linkedin": is_linkedin,
        "has_sales_nav_elements": has_sales_nav_elements,
        "has_search_results": len(result_elements) > 0,
        "result_element_count": len(result_elements),
        "person_element_count": len(person_elements),
        "profile_element_count": len(profile_elements),
        "interesting_classes": sorted(list(set(interesting_classes))),
        "specific_selectors": specific_selectors,
        "access_issues": access_issues,
        "total_elements": len(selector.css("*")),
        "has_javascript_content": "window." in selector.get() or "document." in selector.get(),
    }

async def main():
    if not os.environ.get("SCRAPFLY_API_KEY"):
        log.error("SCRAPFLY_API_KEY environment variable is required")
        return
    
    test_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    await debug_sales_navigator_page(test_url)

if __name__ == "__main__":
    asyncio.run(main())