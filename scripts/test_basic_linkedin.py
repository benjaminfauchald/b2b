#!/usr/bin/env python3
"""
Test basic LinkedIn scraper (profiles and companies) from ScrapFly repository
This is to verify our setup works before attempting Sales Navigator
"""

import os
import json
import asyncio
from typing import Dict, List
from scrapfly import ScrapeConfig, ScrapflyClient
from parsel import Selector

SCRAPFLY = ScrapflyClient(key=os.environ.get("SCRAPFLY_API_KEY"))

# Base configuration based on ScrapFly LinkedIn scraper
BASE_CONFIG = {
    "asp": True,
    "country": "US",
    "headers": {
        "Accept-Language": "en-US,en;q=0.5"
    },
    "render_js": True,
    "proxy_pool": "public_residential_pool"
}

def parse_profile(response) -> Dict:
    """Parse LinkedIn profile page - based on ScrapFly example"""
    selector = response.selector
    
    try:
        # Try to find JSON-LD data
        scripts = selector.css("script[type='application/ld+json']::text").getall()
        
        for script in scripts:
            try:
                data = json.loads(script)
                if isinstance(data, dict) and "@graph" in data:
                    # Find person data
                    person_data = None
                    for item in data["@graph"]:
                        if item.get("@type") == "Person":
                            person_data = item
                            break
                    
                    if person_data:
                        return {
                            "success": True,
                            "name": person_data.get("name", ""),
                            "title": person_data.get("jobTitle", ""),
                            "company": person_data.get("worksFor", [{}])[0].get("name", "") if person_data.get("worksFor") else "",
                            "url": person_data.get("url", ""),
                            "description": person_data.get("description", ""),
                            "source": "json_ld"
                        }
            except:
                continue
        
        # Fallback to HTML parsing
        name = selector.css("h1.text-heading-xlarge::text").get() or ""
        title = selector.css(".text-body-medium.break-words::text").get() or ""
        
        return {
            "success": bool(name),
            "name": name.strip(),
            "title": title.strip(),
            "company": "",
            "url": str(response.context["url"]),
            "description": "",
            "source": "html_parsing"
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "url": str(response.context["url"])
        }

def parse_company(response) -> Dict:
    """Parse LinkedIn company page"""
    selector = response.selector
    
    try:
        # Try JSON-LD first
        scripts = selector.css("script[type='application/ld+json']::text").getall()
        
        for script in scripts:
            try:
                data = json.loads(script)
                if isinstance(data, dict) and "@graph" in data:
                    # Find organization data
                    org_data = None
                    for item in data["@graph"]:
                        if item.get("@type") == "Organization":
                            org_data = item
                            break
                    
                    if org_data:
                        return {
                            "success": True,
                            "name": org_data.get("name", ""),
                            "description": org_data.get("description", ""),
                            "url": org_data.get("url", ""),
                            "logo": org_data.get("logo", ""),
                            "employees": org_data.get("numberOfEmployees", {}).get("value", ""),
                            "address": org_data.get("address", {}),
                            "source": "json_ld"
                        }
            except:
                continue
        
        # Fallback to HTML parsing
        name = selector.css("h1.org-top-card-summary__title::text").get() or ""
        description = selector.css(".org-top-card-summary__tagline::text").get() or ""
        
        return {
            "success": bool(name),
            "name": name.strip(),
            "description": description.strip(),
            "url": str(response.context["url"]),
            "source": "html_parsing"
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "url": str(response.context["url"])
        }

async def scrape_profiles(urls: List[str]) -> List[Dict]:
    """Scrape LinkedIn profile pages"""
    to_scrape = [ScrapeConfig(url, **BASE_CONFIG) for url in urls]
    data = []
    
    async for response in SCRAPFLY.concurrent_scrape(to_scrape):
        try:
            profile_data = parse_profile(response)
            data.append(profile_data)
            print(f"✅ Profile: {profile_data.get('name', 'Unknown')} - {profile_data.get('title', 'No title')}")
        except Exception as e:
            print(f"❌ Failed to parse profile: {e}")
            data.append({"success": False, "error": str(e)})
    
    return data

async def scrape_companies(urls: List[str]) -> List[Dict]:
    """Scrape LinkedIn company pages"""
    to_scrape = [ScrapeConfig(url, **BASE_CONFIG) for url in urls]
    data = []
    
    async for response in SCRAPFLY.concurrent_scrape(to_scrape):
        try:
            company_data = parse_company(response)
            data.append(company_data)
            print(f"✅ Company: {company_data.get('name', 'Unknown')} - {company_data.get('description', 'No description')[:50]}...")
        except Exception as e:
            print(f"❌ Failed to parse company: {e}")
            data.append({"success": False, "error": str(e)})
    
    return data

async def test_basic_linkedin_scraping():
    """Test basic LinkedIn scraping functionality"""
    
    if not os.environ.get("SCRAPFLY_API_KEY"):
        print("❌ SCRAPFLY_API_KEY environment variable is required")
        return
    
    print("🧪 Testing Basic LinkedIn Scraping")
    print("=" * 50)
    
    # Test profile scraping
    print("\n👤 Testing Profile Scraping:")
    profile_urls = [
        "https://www.linkedin.com/in/williamhgates",  # Bill Gates - should be public
        "https://www.linkedin.com/in/satyanadella",   # Satya Nadella - should be public
    ]
    
    profile_results = await scrape_profiles(profile_urls)
    
    # Test company scraping  
    print("\n🏢 Testing Company Scraping:")
    company_urls = [
        "https://linkedin.com/company/microsoft",
        "https://linkedin.com/company/google"
    ]
    
    company_results = await scrape_companies(company_urls)
    
    # Save results
    os.makedirs("tmp", exist_ok=True)
    
    results = {
        "profiles": profile_results,
        "companies": company_results,
        "summary": {
            "successful_profiles": sum(1 for p in profile_results if p.get("success")),
            "total_profiles": len(profile_results),
            "successful_companies": sum(1 for c in company_results if c.get("success")),
            "total_companies": len(company_results)
        }
    }
    
    with open("tmp/basic_linkedin_test.json", "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved to tmp/basic_linkedin_test.json")
    
    # Print summary
    print(f"\n📊 SUMMARY:")
    print(f"✅ Profiles: {results['summary']['successful_profiles']}/{results['summary']['total_profiles']}")
    print(f"✅ Companies: {results['summary']['successful_companies']}/{results['summary']['total_companies']}")
    
    if results['summary']['successful_profiles'] > 0 or results['summary']['successful_companies'] > 0:
        print(f"\n🎉 Basic LinkedIn scraping is WORKING!")
        print(f"Now we can proceed to Sales Navigator with confidence.")
    else:
        print(f"\n⚠️ Basic LinkedIn scraping failed - need to fix setup first")
    
    return results

if __name__ == "__main__":
    asyncio.run(test_basic_linkedin_scraping())