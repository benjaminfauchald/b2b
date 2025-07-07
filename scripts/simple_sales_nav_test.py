#!/usr/bin/env python3
"""
Simple Sales Navigator test - try basic URLs first
"""

import os
import asyncio
from scrapfly import ScrapeConfig, ScrapflyClient

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

async def test_simple_urls():
    """Test simpler Sales Navigator URLs to identify access issues"""
    
    cookies = {"li_at": os.environ.get("LINKEDIN_COOKIE_LI_AT", "")}
    
    test_urls = [
        "https://www.linkedin.com/sales/",
        "https://www.linkedin.com/sales/search/people",
        "https://www.linkedin.com/sales/search/people?keywords=developer",
        "https://www.linkedin.com/feed/"  # Control test
    ]
    
    for url in test_urls:
        print(f"\n🔍 Testing: {url}")
        
        try:
            config = ScrapeConfig(
                url,
                cookies=cookies,
                asp=True,
                country="US",
                render_js=True,
                js="""
                // Simple wait for page load
                new Promise(resolve => {
                    setTimeout(() => {
                        console.log('Page loaded, checking content...');
                        resolve(true);
                    }, 8000);
                });
                """
            )
            
            response = await SCRAPFLY.async_scrape(config)
            
            title = response.selector.css("title::text").get() or "No title"
            content = response.content.lower()
            
            # Check for key indicators
            has_loading = "loading" in content or "initial-load" in content
            has_login_prompt = "sign in" in content or "login" in content
            has_sales_nav = "sales navigator" in content
            has_subscription_prompt = "upgrade" in content or "premium" in content
            has_search_results = "search" in content and "results" in content
            
            print(f"  Status: {response.status_code}")
            print(f"  Title: {title}")
            print(f"  Has Loading: {has_loading}")
            print(f"  Has Login Prompt: {has_login_prompt}")
            print(f"  Has Sales Nav Content: {has_sales_nav}")
            print(f"  Has Subscription Prompt: {has_subscription_prompt}")
            print(f"  Has Search Results: {has_search_results}")
            print(f"  Content Size: {len(response.content)} bytes")
            
            # Save content for this URL
            filename = url.replace("https://", "").replace("/", "_") + ".html"
            with open(f"tmp/debug/{filename}", "w", encoding="utf-8") as f:
                f.write(response.content)
            print(f"  Saved to: tmp/debug/{filename}")
            
        except Exception as e:
            print(f"  ❌ Error: {e}")

if __name__ == "__main__":
    os.makedirs("tmp/debug", exist_ok=True)
    asyncio.run(test_simple_urls())