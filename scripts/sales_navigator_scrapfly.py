#!/usr/bin/env python3
"""
Sales Navigator Scraper using ScrapFly API

This script scrapes LinkedIn Sales Navigator search pages using ScrapFly's
anti-bot protection and rotating proxies. Based on the ScrapFly LinkedIn scraper
but adapted specifically for Sales Navigator pages.

Usage:
    python scripts/sales_navigator_scrapfly.py

Environment variables required:
    SCRAPFLY_API_KEY: Your ScrapFly API key
    LINKEDIN_EMAIL: LinkedIn account email
    LINKEDIN_PASSWORD: LinkedIn account password
    LINKEDIN_COOKIE_LI_AT: LinkedIn authentication cookie (optional, more reliable)
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
    # Bypass LinkedIn's anti-bot protection
    "asp": True,
    # Set proxy country to US for better LinkedIn access
    "country": "US",
    "headers": {
        "Accept-Language": "en-US,en;q=0.5",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    },
    # Enable JavaScript rendering for dynamic content with longer wait time
    "render_js": True,
    "js": "document.readyState === 'complete' && window.location.href.includes('sales')",  # Wait for page to be fully loaded
    # Use residential proxy pool for better success rate
    "proxy_pool": "public_residential_pool",
    # Enable caching for development (disabled when using session)
    "cache": False,
    # Add session management for maintaining LinkedIn authentication
    "session": "linkedin_session"
}

def extract_company_id_from_url(url: str) -> Optional[str]:
    """Extract company ID from Sales Navigator URL"""
    try:
        # Decode URL and extract company ID from filters
        decoded = unquote(url)
        if "id%3A" in url:
            # Extract from encoded URL
            start = url.find("id%3A") + 5
            end = url.find("%2C", start)
            if end == -1:
                end = url.find(")", start)
            return url[start:end]
        elif "id:" in decoded:
            # Extract from decoded URL
            start = decoded.find("id:") + 3
            end = decoded.find(",", start)
            if end == -1:
                end = decoded.find(")", start)
            return decoded[start:end]
    except Exception as e:
        log.error(f"Failed to extract company ID from URL: {e}")
    return None

def build_linkedin_cookies() -> Dict[str, str]:
    """Build LinkedIn cookies from environment variables"""
    cookies = {}
    
    # Add authentication cookie if available
    if os.environ.get("LINKEDIN_COOKIE_LI_AT"):
        cookies["li_at"] = os.environ.get("LINKEDIN_COOKIE_LI_AT")
    
    # Add session cookie if available  
    if os.environ.get("LINKEDIN_COOKIE_JSESSIONID"):
        cookies["JSESSIONID"] = os.environ.get("LINKEDIN_COOKIE_JSESSIONID").strip('"')
    
    # Add other cookies
    if os.environ.get("LINKEDIN_COOKIE_BCOOKIE"):
        cookies["bcookie"] = os.environ.get("LINKEDIN_COOKIE_BCOOKIE").strip('"')
    
    if os.environ.get("LINKEDIN_COOKIE_BSCOOKIE"):
        cookies["bscookie"] = os.environ.get("LINKEDIN_COOKIE_BSCOOKIE").strip('"')
    
    return cookies

def parse_sales_navigator_search(response: ScrapeApiResponse) -> Dict:
    """Parse Sales Navigator search results"""
    selector = response.selector
    results = []
    
    try:
        # Try multiple selectors for Sales Navigator results
        search_results = (
            selector.css("li[data-x-search-result]") or
            selector.css(".search-results__result-item") or 
            selector.css("[data-anonymize='person-name']").xpath("./ancestor::li[1]") or
            selector.css("li").xpath(".//span[contains(@class, 'result')]/..")
        )
        
        log.info(f"Found {len(search_results)} potential result containers")
        
        for idx, result in enumerate(search_results[:20]):  # Limit to first 20 results
            try:
                # Extract profile data using multiple strategies
                profile_data = extract_profile_from_result(result, idx)
                if profile_data and profile_data.get("name"):
                    results.append(profile_data)
            except Exception as e:
                log.debug(f"Failed to parse result {idx}: {e}")
                continue
        
        # Also try to extract from JSON data if available
        json_results = extract_from_json_data(selector)
        if json_results:
            results.extend(json_results)
        
        # Remove duplicates based on name
        seen_names = set()
        unique_results = []
        for result in results:
            name = result.get("name", "").strip()
            if name and name not in seen_names:
                seen_names.add(name)
                unique_results.append(result)
        
        return {
            "results": unique_results,
            "total_found": len(unique_results),
            "url": str(response.context["url"]),
            "success": True
        }
        
    except Exception as e:
        log.error(f"Failed to parse Sales Navigator search: {e}")
        return {
            "results": [],
            "total_found": 0,
            "url": str(response.context["url"]),
            "success": False,
            "error": str(e)
        }

def extract_profile_from_result(result_element, idx: int) -> Optional[Dict]:
    """Extract profile data from a single search result element"""
    try:
        # Multiple strategies for extracting profile information
        name = (
            result_element.css("[data-anonymize='person-name'] span::text").get() or
            result_element.css("span[aria-hidden='true']::text").get() or
            result_element.css(".result-lockup__name a::text").get() or
            result_element.css("a span::text").get() or
            ""
        ).strip()
        
        title = (
            result_element.css("[data-anonymize='person-title']::text").get() or
            result_element.css(".result-lockup__highlight-keyword::text").get() or
            result_element.css(".result-lockup__position::text").get() or
            ""
        ).strip()
        
        company = (
            result_element.css("[data-anonymize='company-name']::text").get() or
            result_element.css(".result-lockup__position-company a::text").get() or
            ""
        ).strip()
        
        location = (
            result_element.css("[data-anonymize='person-location']::text").get() or
            result_element.css(".result-lockup__misc-item::text").get() or
            ""
        ).strip()
        
        # Try to extract profile URL
        profile_url = (
            result_element.css("a::attr(href)").get() or
            ""
        )
        
        if profile_url and not profile_url.startswith("http"):
            profile_url = "https://www.linkedin.com" + profile_url
        
        # Only return if we have at least a name
        if name:
            return {
                "name": name,
                "title": title,
                "company": company,
                "location": location,
                "profile_url": profile_url,
                "result_index": idx
            }
    
    except Exception as e:
        log.debug(f"Failed to extract profile from result {idx}: {e}")
    
    return None

def extract_from_json_data(selector: Selector) -> List[Dict]:
    """Try to extract data from JSON embedded in the page"""
    results = []
    
    try:
        # Look for JSON data in script tags
        scripts = selector.css("script::text").getall()
        
        for script in scripts:
            if "searchResults" in script or "people" in script:
                try:
                    # Try to extract JSON data
                    start = script.find("{")
                    end = script.rfind("}") + 1
                    if start != -1 and end > start:
                        json_data = json.loads(script[start:end])
                        # Process JSON data to extract profiles
                        # This would need to be adapted based on the actual JSON structure
                        log.info("Found JSON data in script, but parsing not implemented yet")
                except:
                    continue
    
    except Exception as e:
        log.debug(f"Failed to extract from JSON data: {e}")
    
    return results

async def scrape_sales_navigator_url(url: str) -> Dict:
    """Scrape a single Sales Navigator URL"""
    try:
        # Build cookies for authentication
        cookies = build_linkedin_cookies()
        
        # Create scrape configuration
        config = ScrapeConfig(
            url,
            cookies=cookies,
            **BASE_CONFIG
        )
        
        log.info(f"Scraping Sales Navigator URL: {url}")
        log.info(f"Using cookies: {list(cookies.keys())}")
        
        # Perform the scrape
        response = await SCRAPFLY.async_scrape(config)
        
        # Parse the results
        parsed_data = parse_sales_navigator_search(response)
        
        # Add metadata
        parsed_data.update({
            "scraped_at": time.time(),
            "company_id": extract_company_id_from_url(url),
            "response_status": response.status_code,
            "response_size": len(response.content)
        })
        
        log.success(f"Successfully scraped {parsed_data['total_found']} profiles")
        return parsed_data
        
    except Exception as e:
        log.error(f"Failed to scrape Sales Navigator URL: {e}")
        return {
            "results": [],
            "total_found": 0,
            "success": False,
            "error": str(e),
            "url": url
        }

async def test_sales_navigator_scraper():
    """Test the Sales Navigator scraper with the provided URL"""
    
    # Check for required environment variables
    if not os.environ.get("SCRAPFLY_API_KEY"):
        log.error("SCRAPFLY_API_KEY environment variable is required")
        return
    
    # Test URL provided by user
    test_url = "https://www.linkedin.com/sales/search/people?query=(filters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3A3341537%2CselectionType%3AINCLUDED)))))&sessionId=cWxbdzEXSJSyuYKPOUjGtw%3D%3D"
    
    log.info("Starting Sales Navigator scraper test")
    log.info(f"Target URL: {test_url}")
    
    # Extract company ID for reference
    company_id = extract_company_id_from_url(test_url)
    log.info(f"Extracted company ID: {company_id}")
    
    # Scrape the URL
    result = await scrape_sales_navigator_url(test_url)
    
    # Save results
    output_file = "tmp/sales_navigator_results.json"
    os.makedirs("tmp", exist_ok=True)
    
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    log.info(f"Results saved to: {output_file}")
    
    # Print summary
    if result["success"]:
        log.success(f"✅ Scraping successful!")
        log.info(f"📊 Found {result['total_found']} profiles")
        log.info(f"🏢 Company ID: {result.get('company_id', 'Unknown')}")
        
        # Print first few results
        for i, profile in enumerate(result["results"][:3]):
            log.info(f"👤 Profile {i+1}: {profile['name']} - {profile['title']} at {profile['company']}")
    else:
        log.error(f"❌ Scraping failed: {result.get('error', 'Unknown error')}")
    
    return result

if __name__ == "__main__":
    # Run the test
    asyncio.run(test_sales_navigator_scraper())