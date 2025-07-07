#!/usr/bin/env python3
"""
Test LinkedIn access to verify authentication and subscription status
"""

import os
import json
import asyncio
from scrapfly import ScrapeConfig, ScrapflyClient

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

async def test_linkedin_access():
    """Test different LinkedIn URLs to verify access levels"""
    
    cookies = {
        "li_at": os.environ.get("LINKEDIN_COOKIE_LI_AT", "")
    }
    
    test_urls = [
        {
            "name": "LinkedIn Homepage",
            "url": "https://www.linkedin.com/feed/",
            "expected": "Should show main LinkedIn feed if authenticated"
        },
        {
            "name": "Sales Navigator Home", 
            "url": "https://www.linkedin.com/sales/",
            "expected": "Should show Sales Navigator dashboard if subscribed"
        },
        {
            "name": "Sales Navigator People Search",
            "url": "https://www.linkedin.com/sales/search/people",
            "expected": "Should show people search page"
        },
        {
            "name": "Public Company Page",
            "url": "https://www.linkedin.com/company/microsoft/",
            "expected": "Should always work (public page)"
        }
    ]
    
    results = []
    
    for test in test_urls:
        print(f"\n🔍 Testing: {test['name']}")
        print(f"URL: {test['url']}")
        print(f"Expected: {test['expected']}")
        
        try:
            config = ScrapeConfig(
                test['url'],
                cookies=cookies,
                asp=True,
                country="US",
                render_js=True
            )
            
            response = await SCRAPFLY.async_scrape(config)
            
            title = response.selector.css("title::text").get() or "No title"
            body_text = response.content[:1000].lower()
            
            # Check for various indicators
            is_authenticated = "sign in" not in body_text and "sign up" not in body_text
            has_sales_nav = "sales navigator" in body_text
            has_premium = "premium" in body_text
            has_error = "error" in body_text or "not found" in body_text
            
            result = {
                "name": test['name'],
                "url": test['url'],
                "status_code": response.status_code,
                "title": title,
                "is_authenticated": is_authenticated,
                "has_sales_nav_content": has_sales_nav,
                "has_premium_content": has_premium,
                "has_error": has_error,
                "content_size": len(response.content)
            }
            
            results.append(result)
            
            print(f"✅ Status: {response.status_code}")
            print(f"📄 Title: {title}")
            print(f"🔐 Authenticated: {is_authenticated}")
            print(f"💼 Sales Nav Content: {has_sales_nav}")
            print(f"⭐ Premium Content: {has_premium}")
            print(f"❌ Has Error: {has_error}")
            
        except Exception as e:
            print(f"❌ Error: {e}")
            results.append({
                "name": test['name'],
                "url": test['url'],
                "error": str(e)
            })
    
    # Save results
    os.makedirs("tmp", exist_ok=True)
    with open("tmp/linkedin_access_test.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n💾 Results saved to tmp/linkedin_access_test.json")
    
    # Summary
    print(f"\n📊 SUMMARY:")
    for result in results:
        if "error" not in result:
            status = "✅" if result.get("is_authenticated") else "❌"
            print(f"{status} {result['name']}: {result['title']}")
        else:
            print(f"❌ {result['name']}: {result['error']}")
    
    return results

if __name__ == "__main__":
    asyncio.run(test_linkedin_access())